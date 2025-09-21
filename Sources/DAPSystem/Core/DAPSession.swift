//
//  DAPSession.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

public final class DAPSession: Sendable {
    public enum State: Sendable {
        case idle
        case starting
        case running
        case stopping
        case terminated
    }

    public let identifier: UUID
    public let manifest: DAPAdapterManifest
    public let configuration: [String: DAPJSONValue]
    public private(set) var state: State = .idle

    /// Emits high-level session events so that observers can react to runtime
    /// activity. The closure is invoked on the broker's internal executor, so
    /// callers should hop to the desired queue or actor as needed.
    public var onEvent: (@Sendable (DAPSessionEvent) -> Void)?

    private let broker: DAPMessageBroker
    private let hostDelegate: DAPSessionHostDelegate?
    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPSession"
    )

    private(set) var capabilities: Set<String> = []
    private var watchExpressions: [DAPWatchExpression] = []
    private var conditionalBreakpoints: [DAPConditionalBreakpoint] = []
    private var lastSynchronizedBreakpointFiles: Set<URL> = []
    private var pendingBreakpointSync: Bool = true
    private var exceptionBreakpointFilters: [String] = []
    private var pendingExceptionBreakpointSync: Bool = true
    private var handshakeContinuation: CheckedContinuation<Void, Error>?

    public init(
        manifest: DAPAdapterManifest,
        configuration: [String: DAPJSONValue],
        broker: DAPMessageBroker,
        hostDelegate: DAPSessionHostDelegate? = nil
    ) {
        self.identifier = UUID()
        self.manifest = manifest
        self.configuration = configuration
        self.broker = broker
        self.hostDelegate = hostDelegate

        registerRuntimeEventHandlers()
        registerHostRequestHandlers()
    }

    public func start() async throws {
        guard state == .idle else { return }
        state = .starting
        logger.log("Starting DAP session for adapter \(manifest.identifier)")

        let requestCommand: String
        if let configuredRequest = configuration["request"]?.stringValue,
            !configuredRequest.isEmpty
        {
            requestCommand = configuredRequest
        } else {
            requestCommand = "launch"
        }

        var requestArguments = configuration
        requestArguments.removeValue(forKey: "request")
        let requestArgumentsValue = DAPJSONValue.object(requestArguments)

        await broker.registerEventHandler(for: "initialized") { [weak self] _ in
            guard let self else { return }
            do {
                let configurationResponse = try await self.broker.sendRequest(
                    command: "configurationDone",
                    arguments: .object([:])
                )

                guard configurationResponse.success else {
                    self.logger.error(
                        "Adapter rejected configurationDone: \(configurationResponse.message ?? "Unknown error")"
                    )
                    self.resumeHandshakeIfNeeded(
                        with: DAPError.adapterUnavailable(
                            configurationResponse.message
                                ?? "configurationDone rejected"
                        )
                    )
                    return
                }

                let requestResponse = try await self.broker.sendRequest(
                    command: requestCommand,
                    arguments: requestArgumentsValue
                )

                guard requestResponse.success else {
                    self.logger.error(
                        "Adapter failed to \(requestCommand): \(requestResponse.message ?? "Unknown error")"
                    )
                    self.resumeHandshakeIfNeeded(
                        with: DAPError.adapterUnavailable(
                            requestResponse.message ?? "Launch/attach failed"
                        )
                    )
                    return
                }

                self.state = .running
                self.emitEvent(.initialized)
                await self.flushPendingSynchronizations()
                self.resumeHandshakeIfNeeded(with: nil)
            } catch {
                self.logger.error(
                    "Failed to complete adapter initialization handshake: \(error.localizedDescription)"
                )
                self.resumeHandshakeIfNeeded(with: error)
            }
        }

        let initializeArguments = DAPJSONValue.object([
            "adapterID": .string(manifest.identifier),
            "pathFormat": .string("path"),
            "supportsVariableType": .bool(true),
            "supportsVariablePaging": .bool(true),
        ])

        let response = try await broker.sendRequest(
            command: "initialize",
            arguments: initializeArguments
        )
        guard response.success else {
            throw DAPError.adapterUnavailable(
                response.message ?? "Unknown initialize failure"
            )
        }

        if let body = response.body?.objectValue,
            let capabilitiesValue = body["capabilities"],
            case .object(let capabilitiesObject) = capabilitiesValue
        {
            capabilities = Set(capabilitiesObject.keys)
        }

        try await withCheckedThrowingContinuation { continuation in
            self.handshakeContinuation = continuation
        }
    }

    public func stop() async {
        guard state == .running else { return }
        state = .stopping
        do {
            _ = try await broker.sendRequest(
                command: "disconnect",
                arguments: .object(["restart": .bool(false)])
            )
        } catch {
            logger.error(
                "Failed to send disconnect to adapter: \(error.localizedDescription)"
            )
        }
        await broker.close()
        state = .terminated
    }

    public func evaluateWatchExpressions() async {
        guard manifest.supportsWatchExpressions else { return }
        guard state == .running else { return }
        for expression in watchExpressions {
            _ = try? await broker.sendRequest(
                command: "evaluate",
                arguments: .object([
                    "expression": .string(expression.expression),
                    "context": .string("watch"),
                ])
            )
        }
    }

    public func updateConditionalBreakpoints(
        _ breakpoints: [DAPConditionalBreakpoint]
    ) {
        guard manifest.supportsConditionalBreakpoints else { return }
        conditionalBreakpoints = breakpoints
        pendingBreakpointSync = true
        scheduleSynchronization()
    }

    public func addWatchExpression(_ expression: DAPWatchExpression) {
        guard manifest.supportsWatchExpressions else { return }
        watchExpressions.append(expression)
    }

    @discardableResult
    public func continueExecution(threadID: Int? = nil) async throws -> Bool {
        let response = try await sendRunControlCommand(
            "continue",
            threadID: threadID
        )
        if let allThreads = response.body?.objectValue?["allThreadsContinued"]?
            .boolValue
        {
            return allThreads
        }
        return true
    }

    public func pause(threadID: Int? = nil) async throws {
        _ = try await sendRunControlCommand("pause", threadID: threadID)
    }

    public func stepIn(threadID: Int) async throws {
        _ = try await sendRunControlCommand("stepIn", threadID: threadID)
    }

    public func stepOut(threadID: Int) async throws {
        _ = try await sendRunControlCommand("stepOut", threadID: threadID)
    }

    public func stepOver(threadID: Int) async throws {
        _ = try await sendRunControlCommand("next", threadID: threadID)
    }

    public func fetchThreads() async throws -> [DAPThread] {
        try ensureSessionIsRunning()
        let response = try await broker.sendRequest(
            command: "threads",
            arguments: nil
        )
        try ensureSuccess(response, context: "threads")
        guard let array = response.body?.objectValue?["threads"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "threads response missing 'threads' array"
            )
        }
        return try array.map { try DAPThread(json: $0) }
    }

    public func fetchStackTrace(
        threadID: Int,
        startFrame: Int? = nil,
        levels: Int? = nil
    ) async throws -> [DAPStackFrame] {
        try ensureSessionIsRunning()
        var arguments: [String: DAPJSONValue] = [
            "threadId": .number(Double(threadID))
        ]
        if let startFrame {
            arguments["startFrame"] = .number(Double(startFrame))
        }
        if let levels {
            arguments["levels"] = .number(Double(levels))
        }

        let response = try await broker.sendRequest(
            command: "stackTrace",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "stackTrace")
        guard
            let frames = response.body?.objectValue?["stackFrames"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "stackTrace response missing 'stackFrames'"
            )
        }
        return try frames.map { try DAPStackFrame(json: $0) }
    }

    public func fetchScopes(frameID: Int) async throws -> [DAPScope] {
        try ensureSessionIsRunning()
        let response = try await broker.sendRequest(
            command: "scopes",
            arguments: .object([
                "frameId": .number(Double(frameID))
            ])
        )
        try ensureSuccess(response, context: "scopes")
        guard let scopes = response.body?.objectValue?["scopes"]?.arrayValue
        else {
            throw DAPError.invalidResponse("scopes response missing 'scopes'")
        }
        return try scopes.map { try DAPScope(json: $0) }
    }

    public func fetchVariables(reference: Int) async throws -> [DAPVariable] {
        try ensureSessionIsRunning()
        let response = try await broker.sendRequest(
            command: "variables",
            arguments: .object([
                "variablesReference": .number(Double(reference))
            ])
        )
        try ensureSuccess(response, context: "variables")
        guard
            let variables = response.body?.objectValue?["variables"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "variables response missing 'variables'"
            )
        }
        return try variables.map { try DAPVariable(json: $0) }
    }

    public func setExceptionBreakpoints(_ filters: [String]) async throws {
        exceptionBreakpointFilters = filters
        pendingExceptionBreakpointSync = true
        try await performSynchronization()
    }

    @discardableResult
    public func setDataBreakpoints(_ breakpoints: [DAPDataBreakpoint])
        async throws -> [DAPDataBreakpointStatus]
    {
        try ensureSessionIsRunning()
        let arguments = DAPJSONValue.object([
            "breakpoints": .array(breakpoints.map { $0.jsonValue() })
        ])
        let response = try await broker.sendRequest(
            command: "setDataBreakpoints",
            arguments: arguments
        )
        try ensureSuccess(response, context: "setDataBreakpoints")
        guard
            let results = response.body?.objectValue?["breakpoints"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "setDataBreakpoints response missing 'breakpoints'"
            )
        }
        return try results.map { try DAPDataBreakpointStatus(json: $0) }
    }

    public func fetchLoadedSources() async throws -> [DAPLoadedSource] {
        try ensureSessionIsRunning()
        let response = try await broker.sendRequest(
            command: "loadedSources",
            arguments: nil
        )
        try ensureSuccess(response, context: "loadedSources")
        guard let sources = response.body?.objectValue?["sources"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "loadedSources response missing 'sources'"
            )
        }
        return try sources.map { try DAPLoadedSource(json: $0) }
    }

    public func fetchModules() async throws -> [DAPModule] {
        try ensureSessionIsRunning()
        let response = try await broker.sendRequest(
            command: "modules",
            arguments: nil
        )
        try ensureSuccess(response, context: "modules")
        guard let modules = response.body?.objectValue?["modules"]?.arrayValue
        else {
            throw DAPError.invalidResponse("modules response missing 'modules'")
        }
        return try modules.map { try DAPModule(json: $0) }
    }

    public func fetchCompletions(
        text: String,
        column: Int,
        line: Int,
        frameID: Int? = nil
    ) async throws -> [DAPCompletionItem] {
        try ensureSessionIsRunning()
        var arguments: [String: DAPJSONValue] = [
            "text": .string(text),
            "column": .number(Double(column)),
            "line": .number(Double(line)),
        ]
        if let frameID {
            arguments["frameId"] = .number(Double(frameID))
        }

        let response = try await broker.sendRequest(
            command: "completions",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "completions")
        guard
            let items = response.body?.objectValue?["targets"]?.arrayValue
                ?? response.body?.objectValue?["items"]?.arrayValue
        else {
            throw DAPError.invalidResponse(
                "completions response missing 'items' or 'targets'"
            )
        }
        return try items.map { try DAPCompletionItem(json: $0) }
    }

    public func readMemory(
        memoryReference: String,
        offset: Int? = nil,
        count: Int
    ) async throws -> DAPReadMemoryResult {
        try ensureSessionIsRunning()
        var arguments: [String: DAPJSONValue] = [
            "memoryReference": .string(memoryReference),
            "count": .number(Double(count)),
        ]
        if let offset {
            arguments["offset"] = .number(Double(offset))
        }

        let response = try await broker.sendRequest(
            command: "readMemory",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "readMemory")
        guard let body = response.body else {
            throw DAPError.invalidResponse("readMemory response missing body")
        }
        return try DAPReadMemoryResult(json: body)
    }

    public func writeMemory(
        memoryReference: String,
        offset: Int? = nil,
        data: Data
    ) async throws -> DAPWriteMemoryResult {
        try ensureSessionIsRunning()
        var arguments: [String: DAPJSONValue] = [
            "memoryReference": .string(memoryReference),
            "data": .string(data.base64EncodedString()),
        ]
        if let offset {
            arguments["offset"] = .number(Double(offset))
        }

        let response = try await broker.sendRequest(
            command: "writeMemory",
            arguments: .object(arguments)
        )
        try ensureSuccess(response, context: "writeMemory")
        guard let body = response.body else {
            throw DAPError.invalidResponse("writeMemory response missing body")
        }
        return try DAPWriteMemoryResult(json: body)
    }

    // MARK: - Internal helpers

    private func resumeHandshakeIfNeeded(with error: Error?) {
        guard let continuation = handshakeContinuation else { return }
        handshakeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func registerHostRequestHandlers() {
        Task { [weak self] in
            guard let self else { return }

            await self.broker.registerRequestHandler(for: "runInTerminal") {
                [weak self] request in
                guard let self else { throw DAPError.sessionNotActive }
                return try await self.handleRunInTerminalRequest(request)
            }

            await self.broker.registerRequestHandler(for: "startDebugging") {
                [weak self] request in
                guard let self else { throw DAPError.sessionNotActive }
                return try await self.handleStartDebuggingRequest(request)
            }
        }
    }

    private func handleRunInTerminalRequest(_ request: DAPRequest)
        async throws -> DAPResponse
    {
        let payload = try DAPRunInTerminalRequest(arguments: request.arguments)
        guard let delegate = hostDelegate else {
            throw DAPError.unsupportedFeature(
                "runInTerminal is not supported without a host delegate"
            )
        }
        let result = try await delegate.session(self, runInTerminal: payload)
        return DAPResponse(
            seq: request.seq,
            requestSeq: request.seq,
            success: true,
            command: request.command,
            message: nil,
            body: result.body
        )
    }

    private func handleStartDebuggingRequest(_ request: DAPRequest)
        async throws -> DAPResponse
    {
        let payload = try DAPStartDebuggingRequest(arguments: request.arguments)
        guard let delegate = hostDelegate else {
            throw DAPError.unsupportedFeature(
                "startDebugging is not supported without a host delegate"
            )
        }
        let result = try await delegate.session(self, startDebugging: payload)
        return DAPResponse(
            seq: request.seq,
            requestSeq: request.seq,
            success: true,
            command: request.command,
            message: nil,
            body: result.body
        )
    }

    private func registerRuntimeEventHandlers() {
        Task { [weak self] in
            guard let self else { return }

            await self.broker.registerEventHandler(for: "stopped") {
                [weak self] event in
                guard let self else { return }
                guard let body = event.body else { return }
                do {
                    let payload = try DAPStoppedEvent(json: body)
                    self.emitEvent(.stopped(payload))
                } catch {
                    self.logger.error(
                        "Failed to decode stopped event: \(error.localizedDescription)"
                    )
                }
            }

            await self.broker.registerEventHandler(for: "continued") {
                [weak self] event in
                guard let self else { return }
                self.state = .running
                if let body = event.body {
                    do {
                        let payload = try DAPContinuedEvent(json: body)
                        self.emitEvent(.continued(payload))
                    } catch {
                        self.logger.error(
                            "Failed to decode continued event: \(error.localizedDescription)"
                        )
                    }
                } else {
                    self.emitEvent(
                        .continued(
                            DAPContinuedEvent(
                                threadId: nil,
                                allThreadsContinued: nil
                            )
                        )
                    )
                }
            }

            await self.broker.registerEventHandler(for: "terminated") {
                [weak self] event in
                guard let self else { return }
                self.state = .terminated
                if let body = event.body {
                    do {
                        let payload = try DAPTerminatedEvent(json: body)
                        self.emitEvent(.terminated(payload))
                    } catch {
                        self.logger.error(
                            "Failed to decode terminated event: \(error.localizedDescription)"
                        )
                    }
                } else {
                    self.emitEvent(
                        .terminated(DAPTerminatedEvent(restart: nil))
                    )
                }
            }

            await self.broker.registerEventHandler(for: "output") {
                [weak self] event in
                guard let self else { return }
                guard let body = event.body else { return }
                do {
                    let payload = try DAPOutputEvent(json: body)
                    self.emitEvent(.output(payload))
                } catch {
                    self.logger.error(
                        "Failed to decode output event: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func emitEvent(_ event: DAPSessionEvent) {
        onEvent?(event)
    }

    private func scheduleSynchronization() {
        guard state == .running else { return }
        Task { [weak self] in
            await self?.flushPendingSynchronizations()
        }
    }

    private func flushPendingSynchronizations() async {
        do {
            try await performSynchronization()
        } catch {
            logger.error(
                "Failed to synchronize breakpoints: \(error.localizedDescription)"
            )
        }
    }

    private func performSynchronization() async throws {
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
                try await sendExceptionBreakpointUpdates()
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
            let breakpointValues: [DAPJSONValue] = breakpoints.map {
                breakpoint in
                var object: [String: DAPJSONValue] = [
                    "line": .number(Double(breakpoint.line))
                ]
                if let condition = breakpoint.condition.isEmpty
                    ? nil : breakpoint.condition
                {
                    object["condition"] = .string(condition)
                }
                if let hitCondition = breakpoint.hitCondition {
                    object["hitCondition"] = .string(hitCondition)
                }
                if let logMessage = breakpoint.logMessage {
                    object["logMessage"] = .string(logMessage)
                }
                return .object(object)
            }

            let sourceObject: [String: DAPJSONValue] = [
                "name": .string(file.lastPathComponent),
                "path": .string(file.path),
            ]

            let arguments = DAPJSONValue.object([
                "source": .object(sourceObject),
                "breakpoints": .array(breakpointValues),
            ])

            let response = try await broker.sendRequest(
                command: "setBreakpoints",
                arguments: arguments
            )

            try ensureSuccess(
                response,
                context: "setBreakpoints for \(file.path)"
            )
        }

        lastSynchronizedBreakpointFiles = Set(grouped.keys)
    }

    private func sendExceptionBreakpointUpdates() async throws {
        let arguments = DAPJSONValue.object([
            "filters": .array(exceptionBreakpointFilters.map { .string($0) })
        ])
        let response = try await broker.sendRequest(
            command: "setExceptionBreakpoints",
            arguments: arguments
        )
        try ensureSuccess(response, context: "setExceptionBreakpoints")
    }

    @discardableResult
    private func sendRunControlCommand(
        _ command: String,
        threadID: Int?,
        additionalArguments: [String: DAPJSONValue] = [:]
    ) async throws -> DAPResponse {
        try ensureSessionIsRunning()
        var arguments = additionalArguments
        if let threadID {
            arguments["threadId"] = .number(Double(threadID))
        }
        let argumentsValue =
            arguments.isEmpty ? nil : DAPJSONValue.object(arguments)
        let response = try await broker.sendRequest(
            command: command,
            arguments: argumentsValue
        )
        try ensureSuccess(response, context: command)
        return response
    }

    private func ensureSuccess(_ response: DAPResponse, context: String) throws
    {
        guard response.success else {
            throw DAPError.adapterUnavailable(
                response.message ?? "\(context) failed"
            )
        }
    }

    private func ensureSessionIsRunning() throws {
        guard state == .running else {
            throw DAPError.sessionNotActive
        }
    }
}
