//
//  DAPSession+Breakpoints.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

extension DAPSession {
    internal func performSynchronization() async throws {
        guard state == .running else { return }
        if pendingBreakpointSync {
            pendingBreakpointSync = false
            do {
                try await sendBreakpointUpdates()
            } catch {
                pendingBreakpointSync = true
                throw error
            }
        }

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

    private func sendBreakpointUpdates() async throws {
        let grouped = Dictionary(
            grouping: conditionalBreakpoints,
            by: { $0.fileURL }
        )
        let filesToUpdate = Set(grouped.keys).union(
            lastSynchronizedBreakpointFiles
        )

        for file in filesToUpdate {
            let breakpoints = grouped[file] ?? []
            let sourceBreakpoints = breakpoints.map { breakpoint in
                DAPSourceBreakpoint(
                    line: breakpoint.line,
                    condition: breakpoint.condition.isEmpty
                        ? nil : breakpoint.condition,
                    hitCondition: breakpoint.hitCondition,
                    logMessage: breakpoint.logMessage
                )
            }

            let source = DAPSource(
                name: file.lastPathComponent,
                path: file,
                sourceReference: nil
            )

            _ = try await setBreakpoints(
                for: source,
                breakpoints: sourceBreakpoints
            )
        }

        lastSynchronizedBreakpointFiles = Set(grouped.keys)
    }

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

    @discardableResult
    func setBreakpoints(
        for source: DAPSource,
        breakpoints: [DAPSourceBreakpoint],
        lines: [Int]? = nil,
        sourceModified: Bool? = nil
    ) async throws -> [DAPBreakpoint] {
        try ensureSessionIsRunning()

        var arguments: [String: DAPJSONValue] = [
            "source": source.asDAPRequestValue(),
            "breakpoints": .array(breakpoints.map { $0.jsonValue() }),
        ]

        if let lines, !lines.isEmpty {
            arguments["lines"] = .array(lines.map { .number(Double($0)) })
        }
        if let sourceModified {
            arguments["sourceModified"] = .bool(sourceModified)
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
    func setFunctionBreakpoints(
        _ breakpoints: [DAPFunctionBreakpoint]
    ) async throws -> [DAPBreakpoint] {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsFunctionBreakpoints",
            feature: "setFunctionBreakpoints"
        )

        let response = try await broker.sendRequest(
            command: "setFunctionBreakpoints",
            arguments: .object([
                "breakpoints": .array(breakpoints.map { $0.jsonValue() })
            ])
        )
        try ensureSuccess(response, context: "setFunctionBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setFunctionBreakpoints"
        )
    }

    @discardableResult
    func setInstructionBreakpoints(
        _ breakpoints: [DAPInstructionBreakpoint]
    ) async throws -> [DAPBreakpoint] {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsInstructionBreakpoints",
            feature: "setInstructionBreakpoints"
        )

        let response = try await broker.sendRequest(
            command: "setInstructionBreakpoints",
            arguments: .object([
                "breakpoints": .array(breakpoints.map { $0.jsonValue() })
            ])
        )
        try ensureSuccess(response, context: "setInstructionBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: true,
            context: "setInstructionBreakpoints"
        )
    }

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

        guard state == .running else {
            return []
        }

        pendingExceptionBreakpointSync = false
        do {
            return try await sendExceptionBreakpointUpdates()
        } catch {
            pendingExceptionBreakpointSync = true
            throw error
        }
    }

    @discardableResult
    func setDataBreakpoints(
        _ breakpoints: [DAPDataBreakpoint]
    ) async throws -> [DAPBreakpoint] {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsDataBreakpoints",
            feature: "setDataBreakpoints"
        )

        let response = try await broker.sendRequest(
            command: "setDataBreakpoints",
            arguments: .object([
                "breakpoints": .array(breakpoints.map { $0.jsonValue() })
            ])
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

        var arguments: [String: DAPJSONValue] = [
            "source": source.asDAPRequestValue(),
            "line": .number(Double(line)),
        ]
        if let column {
            arguments["column"] = .number(Double(column))
        }
        if let endLine {
            arguments["endLine"] = .number(Double(endLine))
        }
        if let endColumn {
            arguments["endColumn"] = .number(Double(endColumn))
        }

        let response = try await broker.sendRequest(
            command: "breakpointLocations",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "breakpointLocations")
        guard
            let locations = response.body?.objectValue?["breakpoints"]?
                .arrayValue
        else {
            throw DAPError.invalidResponse(
                "breakpointLocations response missing 'breakpoints'"
            )
        }
        return try locations.map { try DAPBreakpointLocation(json: $0) }
    }

    func setExpression(
        expression: String,
        value: String,
        frameID: Int? = nil,
        format: DAPValueFormat? = nil
    ) async throws -> DAPSetExpressionResult {
        try ensureSessionIsRunning()
        try requireCapability(
            "supportsSetExpression",
            feature: "setExpression"
        )

        var arguments: [String: DAPJSONValue] = [
            "expression": .string(expression),
            "value": .string(value),
        ]
        if let frameID {
            arguments["frameId"] = .number(Double(frameID))
        }
        if let format {
            arguments["format"] = format.jsonValue()
        }

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
        try requireCapability(
            "supportsSetVariable",
            feature: "setVariable"
        )

        var arguments: [String: DAPJSONValue] = [
            "variablesReference": .number(Double(containerReference)),
            "name": .string(name),
            "value": .string(value),
        ]
        if let format {
            arguments["format"] = format.jsonValue()
        }

        let response = try await broker.sendRequest(
            command: "setVariable",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setVariable")
        guard let body = response.body else {
            throw DAPError.invalidResponse(
                "setVariable response missing body"
            )
        }
        return try DAPSetVariableResult(json: body)
    }
}

extension DAPSession {
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
            let breakpointsValue = body.objectValue?["breakpoints"],
            let breakpointsArray = breakpointsValue.arrayValue
        else {
            if required {
                throw DAPError.invalidResponse(
                    "\(context) response missing 'breakpoints'"
                )
            }
            return []
        }

        return try breakpointsArray.map { try DAPBreakpoint(json: $0) }
    }

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

        var arguments: [String: DAPJSONValue] = [
            "filters": .array(filters.map { .string($0) })
        ]
        if !filterOptions.isEmpty {
            arguments["filterOptions"] = .array(
                filterOptions.map { $0.jsonValue() }
            )
        }
        if !exceptionOptions.isEmpty {
            arguments["exceptionOptions"] = .array(
                exceptionOptions.map { $0.jsonValue() }
            )
        }

        let response = try await broker.sendRequest(
            command: "setExceptionBreakpoints",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "setExceptionBreakpoints")
        return try parseBreakpoints(
            from: response.body,
            required: false,
            context: "setExceptionBreakpoints"
        )
    }
}
