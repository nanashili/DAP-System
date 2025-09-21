//
//  DAPMessageBroker.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

/// Abstract transport interface for wire-agnostic DAP communication.
/// Implementations manage serialization, framing, and IO.
public protocol DAPTransport: AnyObject, Sendable {
    /// Begins receiving messages; emits each as a Result.
    func startReceiving(
        _ handler: @escaping @Sendable (Result<DAPMessage, DAPError>) -> Void
    )
    /// Sends a message to the wire (request, response, or event).
    func send(_ message: DAPMessage) throws
    /// Immediately closes the transport and releases resources.
    func close()
}

/// Central broker for DAP message flow: request/response dispatch, event delivery, and handler registration.
/// Handles out-of-order responses, actor isolation, and error resilience.
public actor DAPMessageBroker {
    public typealias RequestHandler =
        @Sendable (DAPRequest) async throws -> DAPResponse
    public typealias EventHandler = @Sendable (DAPEvent) async -> Void

    private let transport: DAPTransport
    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPMessageBroker"
    )

    private var nextSequence: Int = 1
    private var pendingRequests:
        [Int: CheckedContinuation<DAPResponse, Error>] = [:]
    private var requestHandlers: [String: RequestHandler] = [:]
    private var eventHandlers: [String: [EventHandler]] = [:]

    public init(transport: DAPTransport) {
        self.transport = transport
        transport.startReceiving { [weak self] result in
            guard let self else { return }
            Task { await self.handle(result) }
        }
    }

    /// Registers a handler for an incoming request of a given command.
    public func registerRequestHandler(
        for command: String,
        handler: @escaping RequestHandler
    ) {
        requestHandlers[command] = handler
    }

    /// Registers a handler for a named event.
    public func registerEventHandler(
        for event: String,
        handler: @escaping EventHandler
    ) {
        eventHandlers[event, default: []].append(handler)
    }

    /// Sends a DAP request and waits for the response, handling sequence bookkeeping.
    public func sendRequest(command: String, arguments: DAPJSONValue?)
        async throws -> DAPResponse
    {
        let seq = nextSequence
        nextSequence &+= 1

        let request = DAPRequest(
            seq: seq,
            command: command,
            arguments: arguments
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[seq] = continuation
            do {
                try transport.send(.request(request))
            } catch {
                pendingRequests.removeValue(forKey: seq)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Fires an event to the remote peer. Events do not expect a response.
    public func sendEvent(name: String, body: DAPJSONValue?) throws {
        let event = DAPEvent(seq: nextSequence, event: name, body: body)
        nextSequence &+= 1
        try transport.send(.event(event))
    }

    /// Closes the broker and underlying transport.
    public func close() {
        transport.close()
    }

    // MARK: - Message Routing (internal)

    private func handle(_ result: Result<DAPMessage, DAPError>) async {
        switch result {
        case .success(let message): await route(message)
        case .failure(let error):
            logger.error("Transport failure: \(error.localizedDescription)")
        }
    }

    private func route(_ message: DAPMessage) async {
        switch message {
        case .request(let request): await handleIncomingRequest(request)
        case .response(let response): handleResponse(response)
        case .event(let event): await handleEvent(event)
        }
    }

    /// Handles incoming requests (from server or peer).
    /// Executes the registered handler and sends a response, catching and reporting any errors.
    private func handleIncomingRequest(_ request: DAPRequest) async {
        guard let handler = requestHandlers[request.command] else {
            logger.error("No handler for DAP request '\(request.command)'")
            let response = DAPResponse(
                seq: nextSequence,
                requestSeq: request.seq,
                success: false,
                command: request.command,
                message: "Unsupported request: \(request.command)",
                body: nil
            )
            nextSequence &+= 1
            try? transport.send(.response(response))
            return
        }
        do {
            let handlerResponse = try await handler(request)
            let response = DAPResponse(
                seq: nextSequence,
                requestSeq: request.seq,
                success: handlerResponse.success,
                command: handlerResponse.command,
                message: handlerResponse.message,
                body: handlerResponse.body
            )
            nextSequence &+= 1
            try transport.send(.response(response))
        } catch {
            let response = DAPResponse(
                seq: nextSequence,
                requestSeq: request.seq,
                success: false,
                command: request.command,
                message: error.localizedDescription,
                body: nil
            )
            nextSequence &+= 1
            try? transport.send(.response(response))
        }
    }

    /// Delivers a response to the correct awaiting request continuation.
    private func handleResponse(_ response: DAPResponse) {
        guard
            let continuation = pendingRequests.removeValue(
                forKey: response.requestSeq
            )
        else {
            logger.error(
                "Received response for unknown request seq \(response.requestSeq)"
            )
            return
        }
        continuation.resume(returning: response)
    }

    /// Delivers an event to all registered event handlers.
    private func handleEvent(_ event: DAPEvent) async {
        guard let handlers = eventHandlers[event.event] else { return }
        for handler in handlers {
            await handler(event)
        }
    }
}
