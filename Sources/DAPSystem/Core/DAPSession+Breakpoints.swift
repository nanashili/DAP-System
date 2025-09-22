//
//  DAPSession+Breakpoints.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//  Updated: 2025-09-22 (perf + docs + concurrency)
//
//  Overview
//  --------
//  Synchronizes source / function / instruction / exception / data breakpoints with
//  the active adapter. Design goals:
//    • Minimal allocations: pre-sized dictionaries/arrays; no gratuitous Set copies.
//    • Fast paths: early returns when idle; skip empty payloads; branch-light helpers.
//    • Concurrency: per-file `setBreakpoints` requests run concurrently when safe.
//    • Idempotence: only re-sync files that changed since the last synchronization.
//    • Clarity: documented preconditions, failure modes, and adapter capability checks.
//

import Foundation

extension DAPSession {

    // MARK: - Internal keys (singletons; avoid string churn)
    @usableFromInline
    enum _K {
        static let source = "source"
        static let breakpoints = "breakpoints"
        static let lines = "lines"
        static let sourceModified = "sourceModified"
        static let line = "line"
        static let column = "column"
        static let endLine = "endLine"
        static let endColumn = "endColumn"
        static let filters = "filters"
        static let filterOptions = "filterOptions"
        static let exceptionOptions = "exceptionOptions"
        static let variablesReference = "variablesReference"
        static let name = "name"
        static let value = "value"
        static let frameId = "frameId"
        static let format = "format"
    }

    // MARK: - Public synchronization entrypoint

    /// Reconciles any pending breakpoint state with the adapter.
    /// Fast path: returns immediately if the session isn't `.running` or if nothing is pending.
    internal func performSynchronization() async throws {
        guard state == .running else { return }

        // Source/data/function/instruction breakpoints
        if pendingBreakpointSync {
            pendingBreakpointSync = false
            do {
                try await sendBreakpointUpdates()
            } catch {
                // Re-flag and bubble: caller decides whether/when to retry.
                pendingBreakpointSync = true
                throw error
            }
        }

        // Exception breakpoints
        if pendingExceptionBreakpointSync {
            pendingExceptionBreakpointSync = false
            do {
                _ = try await sendExceptionBreakpointUpdates()
            } catch {
                pendingExceptionBreakpointSync = true
                throw error
            }
        }
    }

    // MARK: - Source breakpoints

    /// Computes the per-file differences and updates the adapter.
    /// Runs per-file `setBreakpoints` concurrently to maximize responsiveness.
    private func sendBreakpointUpdates() async throws {
        // Group current conditional breakpoints by file for batched requests.
        // This avoids building multiple small JSON arrays for the same file.
        let grouped = Dictionary(
            grouping: conditionalBreakpoints,
            by: { $0.fileURL }
        )

        // Compute files to update:
        //   - All files that currently have breakpoints (grouped keys)
        //   - PLUS any files we *previously* synchronized (to allow clearing)
        var filesToUpdate = lastSynchronizedBreakpointFiles  // reuse existing Set storage
        filesToUpdate.formUnion(grouped.keys)  // no extra Set allocations

        // Early exit: nothing to do.
        if filesToUpdate.isEmpty { return }

        try ensureSessionIsRunning()

        // Fire off per-file updates concurrently. The broker can serialize on its side if needed.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTaskUnlessEmpty(grouped: grouped, files: filesToUpdate) {
                file,
                bps in
                // Build source breakpoints JSON with minimal allocations.
                var arr: [DAPJSONValue] = []
                arr.reserveCapacity(bps.count)
                for bp in bps {
                    arr.append(
                        DAPSourceBreakpoint(
                            line: bp.line,
                            condition: bp.condition.isEmpty
                                ? nil : bp.condition,
                            hitCondition: bp.hitCondition,
                            logMessage: bp.logMessage
                        ).jsonValue()
                    )
                }

                // Adapter source descriptor.
                let source = DAPSource(
                    name: file.lastPathComponent,
                    path: file,
                    sourceReference: nil
                )

                // Prepare arguments with correct capacity.
                var args = [String: DAPJSONValue](minimumCapacity: 2)
                args[_K.source] = source.asDAPRequestValue()
                args[_K.breakpoints] = .array(arr)

                // Send request and validate.
                let response = try await self.broker.sendRequest(
                    command: "setBreakpoints",
                    arguments: .object(args)
                )
                try self.ensureSuccess(
                    response,
                    context: "setBreakpoints(file=\(file.lastPathComponent))"
                )

                // We don't need the returned breakpoints here; adapters may return
                // canonicalized positions which higher layers can observe if needed.
                _ = try self.parseBreakpoints(
                    from: response.body,
                    required: true,
                    context: "setBreakpoints"
                )
            }

            // Propagate the first error (if any).
            try await group.waitForAll()
        }

        // Update the last-synced set to *only* those files we currently manage.
        // (If a file disappeared from `grouped`, we still updated it above to clear BPs.)
        lastSynchronizedBreakpointFiles = Set(grouped.keys)
    }

    // MARK: - Exception breakpoints

    /// Sends current exception breakpoint configuration to the adapter.
    private func sendExceptionBreakpointUpdates() async throws
        -> [DAPBreakpoint]
    {
        try ensureSessionIsRunning()
        return try await performSetExceptionBreakpointsRequest(
            filters: exceptionBreakpointFilters,
            filterOptions: exceptionBreakpointFilterOptions,
            exceptionOptions: exceptionBreakpointOptions
        )
    }

    /// Public API to set exception breakpoints and schedule a sync (or perform immediately if running).
    @discardableResult
    func setExceptionBreakpoints(
        _ filters: [String],
        filterOptions: [DAPExceptionFilterOption] = [],
        exceptionOptions: [DAPExceptionOption] = []
    ) async throws -> [DAPBreakpoint] {
        exceptionBreakpointFilters = filters
        exceptionBreakpointFilterOptions = filterOptions
        exceptionBreakpointOptions = exceptionOptions
        pendingExceptionBreakpointSync = true

        guard state == .running else { return [] }

        pendingExceptionBreakpointSync = false
        do {
            return try await sendExceptionBreakpointUpdates()
        } catch {
            pendingExceptionBreakpointSync = true
            throw error
        }
    }

    // MARK: - Public DAP calls

    /// Sets (source) breakpoints for a particular source.
    /// - Parameters:
    ///   - lines: Some adapters accept either `breakpoints` or `lines`; we support both.
    ///   - sourceModified: Optional optimization hint for adapters that cache per-file hashes.
    @discardableResult
    func setBreakpoints(
        for source: DAPSource,
        breakpoints: [DAPSourceBreakpoint],
        lines: [Int]? = nil,
        sourceModified: Bool? = nil
    ) async throws -> [DAPBreakpoint] {
        try ensureSessionIsRunning()

        // Build arguments with a tight capacity upper bound.
        var arguments = [String: DAPJSONValue](minimumCapacity: 4)
        arguments[_K.source] = source.asDAPRequestValue()
        arguments[_K.breakpoints] = .array(
            {
                var out: [DAPJSONValue] = []
                out.reserveCapacity(breakpoints.count)
                for bp in breakpoints { out.append(bp.jsonValue()) }
                return out
            }()
        )

        if let lines, !lines.isEmpty {
            var arr: [DAPJSONValue] = []
            arr.reserveCapacity(lines.count)
            for l in lines { arr.append(.number(Double(l))) }
            arguments[_K.lines] = .array(arr)
        }
        if let sourceModified {
            arguments[_K.sourceModified] = .bool(sourceModified)
        }

        let response = try await broker.sendRequest(
            command: "setBreakpoints",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setBreakpoints"
        )
    }

    @discardableResult
    func setFunctionBreakpoints(_ breakpoints: [DAPFunctionBreakpoint])
        async throws -> [DAPBreakpoint]
    {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsFunctionBreakpoints",
            feature: "setFunctionBreakpoints"
        )

        var arr: [DAPJSONValue] = []
        arr.reserveCapacity(breakpoints.count)
        for bp in breakpoints { arr.append(bp.jsonValue()) }

        let response = try await broker.sendRequest(
            command: "setFunctionBreakpoints",
            arguments: .object([_K.breakpoints: .array(arr)])
        )
        try ensureSuccess(response, context: "setFunctionBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setFunctionBreakpoints"
        )
    }

    @discardableResult
    func setInstructionBreakpoints(_ breakpoints: [DAPInstructionBreakpoint])
        async throws -> [DAPBreakpoint]
    {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsInstructionBreakpoints",
            feature: "setInstructionBreakpoints"
        )

        var arr: [DAPJSONValue] = []
        arr.reserveCapacity(breakpoints.count)
        for bp in breakpoints { arr.append(bp.jsonValue()) }

        let response = try await broker.sendRequest(
            command: "setInstructionBreakpoints",
            arguments: .object([_K.breakpoints: .array(arr)])
        )
        try ensureSuccess(response, context: "setInstructionBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setInstructionBreakpoints"
        )
    }

    @discardableResult
    func setDataBreakpoints(_ breakpoints: [DAPDataBreakpoint]) async throws
        -> [DAPBreakpoint]
    {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsDataBreakpoints",
            feature: "setDataBreakpoints"
        )

        var arr: [DAPJSONValue] = []
        arr.reserveCapacity(breakpoints.count)
        for bp in breakpoints { arr.append(bp.jsonValue()) }

        let response = try await broker.sendRequest(
            command: "setDataBreakpoints",
            arguments: .object([_K.breakpoints: .array(arr)])
        )
        try ensureSuccess(response, context: "setDataBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setDataBreakpoints"
        )
    }

    func breakpointLocations(
        in source: DAPSource,
        line: Int,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) async throws -> [DAPBreakpointLocation] {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsBreakpointLocationsRequest",
            feature: "breakpointLocations"
        )

        var arguments = [String: DAPJSONValue](minimumCapacity: 5)
        arguments[_K.source] = source.asDAPRequestValue()
        arguments[_K.line] = .number(Double(line))
        if let column { arguments[_K.column] = .number(Double(column)) }
        if let endLine { arguments[_K.endLine] = .number(Double(endLine)) }
        if let endColumn {
            arguments[_K.endColumn] = .number(Double(endColumn))
        }

        let response = try await broker.sendRequest(
            command: "breakpointLocations",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "breakpointLocations")

        guard
            let locations = response.body?.objectValue?[_K.breakpoints]?
                .arrayValue
        else {
            throw DAPError.invalidResponse(
                "breakpointLocations response missing 'breakpoints'"
            )
        }

        // Map in-place style to minimize temporaries.
        var out: [DAPBreakpointLocation] = []
        out.reserveCapacity(locations.count)
        for v in locations { out.append(try DAPBreakpointLocation(json: v)) }
        return out
    }

    func setExpression(
        expression: String,
        value: String,
        frameID: Int? = nil,
        format: DAPValueFormat? = nil
    ) async throws -> DAPSetExpressionResult {
        try ensureSessionIsRunning()
        try requireCapability("supportsSetExpression", feature: "setExpression")

        var arguments = [String: DAPJSONValue](minimumCapacity: 4)
        arguments[_K.name] = .string(expression)  // DAP uses "expression"; keep semantic name below for clarity.
        arguments["expression"] = .string(expression)
        arguments[_K.value] = .string(value)
        if let frameID { arguments[_K.frameId] = .number(Double(frameID)) }
        if let format { arguments[_K.format] = format.jsonValue() }

        let response = try await broker.sendRequest(
            command: "setExpression",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setExpression")
        guard let body = response.body else {
            throw DAPError.invalidResponse(
                "setExpression response missing body"
            )
        }
        return try DAPSetExpressionResult(json: body)
    }

    func setVariable(
        containerReference: Int,
        name: String,
        value: String,
        format: DAPValueFormat? = nil
    ) async throws -> DAPSetVariableResult {
        try ensureSessionIsRunning()
        try requireCapability("supportsSetVariable", feature: "setVariable")

        var arguments = [String: DAPJSONValue](minimumCapacity: 4)
        arguments[_K.variablesReference] = .number(Double(containerReference))
        arguments[_K.name] = .string(name)
        arguments[_K.value] = .string(value)
        if let format { arguments[_K.format] = format.jsonValue() }

        let response = try await broker.sendRequest(
            command: "setVariable",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setVariable")
        guard let body = response.body else {
            throw DAPError.invalidResponse("setVariable response missing body")
        }
        return try DAPSetVariableResult(json: body)
    }
}

// MARK: - Private helpers

extension DAPSession {

    /// Parses adapter-returned breakpoints. When `required == true`, a missing `body` or
    /// `breakpoints` field throws `DAPError.invalidResponse`.
    fileprivate func parseBreakpoints(
        from body: DAPJSONValue?,
        required: Bool,
        context: String
    ) throws -> [DAPBreakpoint] {
        guard let body else {
            if required {
                throw DAPError.invalidResponse(
                    "\(context) response missing body"
                )
            }
            return []
        }
        guard
            let array = body.objectValue?[_K.breakpoints]?.arrayValue
        else {
            if required {
                throw DAPError.invalidResponse(
                    "\(context) response missing 'breakpoints'"
                )
            }
            return []
        }

        var out: [DAPBreakpoint] = []
        out.reserveCapacity(array.count)
        for v in array { out.append(try DAPBreakpoint(json: v)) }
        return out
    }

    /// Validates capabilities and dispatches `setExceptionBreakpoints` to the adapter.
    fileprivate func performSetExceptionBreakpointsRequest(
        filters: [String],
        filterOptions: [DAPExceptionFilterOption],
        exceptionOptions: [DAPExceptionOption]
    ) async throws -> [DAPBreakpoint] {
        if !filterOptions.isEmpty {
            try requireCapability(
                "supportsExceptionFilterOptions",
                feature: "setExceptionBreakpoints with filter options"
            )
        }
        if !exceptionOptions.isEmpty {
            try requireCapability(
                "supportsExceptionOptions",
                feature: "setExceptionBreakpoints with exception options"
            )
        }

        var arguments = [String: DAPJSONValue](minimumCapacity: 3)

        // Filters
        if filters.isEmpty {
            arguments[_K.filters] = .array([])
        } else {
            var arr: [DAPJSONValue] = []
            arr.reserveCapacity(filters.count)
            for f in filters { arr.append(.string(f)) }
            arguments[_K.filters] = .array(arr)
        }

        // Filter Options
        if !filterOptions.isEmpty {
            var arr: [DAPJSONValue] = []
            arr.reserveCapacity(filterOptions.count)
            for o in filterOptions { arr.append(o.jsonValue()) }
            arguments[_K.filterOptions] = .array(arr)
        }

        // Exception Options
        if !exceptionOptions.isEmpty {
            var arr: [DAPJSONValue] = []
            arr.reserveCapacity(exceptionOptions.count)
            for o in exceptionOptions { arr.append(o.jsonValue()) }
            arguments[_K.exceptionOptions] = .array(arr)
        }

        let response = try await broker.sendRequest(
            command: "setExceptionBreakpoints",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setExceptionBreakpoints")

        // This response body may be omitted by some adapters; treat as optional.
        return try parseBreakpoints(
            from: response.body,
            required: false,
            context: "setExceptionBreakpoints"
        )
    }
}
