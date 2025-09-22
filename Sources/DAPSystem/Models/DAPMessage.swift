//
//  DAPMessage.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

// MARK: - Message Kind

/// DAP wire-level message discriminator.
@frozen
public enum DAPMessageType: String, Codable, Sendable {
    case request
    case response
    case event
}

// MARK: - Common protocol

/// Common surface shared by request/response/event.
/// Conformance is trivial and keeps polymorphic handling simple & fast.
public protocol DAPAnyMessage: Codable, Sendable {
    /// Monotonic sequence number (DAP “seq”).
    var seq: Int { get }
    /// Discriminator matching the concrete shape.
    var type: DAPMessageType { get }
}

// MARK: - Request

/// Outbound command from client → adapter.
@frozen
public struct DAPRequest: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    /// Command name as defined by DAP / adapter (e.g., "initialize", "setBreakpoints").
    public let command: String
    /// Optional command arguments (free-form JSON).
    public let arguments: DAPJSONValue?

    @inlinable
    public init(seq: Int, command: String, arguments: DAPJSONValue? = nil) {
        self.seq = seq
        self.type = .request
        self.command = command
        self.arguments = arguments
    }
}

// MARK: - Response

/// Adapter response to a specific request.
@frozen
public struct DAPResponse: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    /// The request sequence this response corresponds to.
    public let requestSeq: Int
    /// Whether the request succeeded at the adapter level.
    public let success: Bool
    /// Command echoed by the adapter (per DAP).
    public let command: String
    /// Optional human-readable failure message.
    public let message: String?
    /// Optional response body (free-form JSON).
    public let body: DAPJSONValue?

    @inlinable
    public init(
        seq: Int,
        requestSeq: Int,
        success: Bool,
        command: String,
        message: String? = nil,
        body: DAPJSONValue? = nil
    ) {
        self.seq = seq
        self.type = .response
        self.requestSeq = requestSeq
        self.success = success
        self.command = command
        self.message = message
        self.body = body
    }
}

// MARK: - Event

/// Asynchronous notification pushed by the adapter.
@frozen
public struct DAPEvent: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    /// Event name (e.g., "initialized", "stopped", "continued").
    public let event: String
    /// Optional event payload (free-form JSON).
    public let body: DAPJSONValue?

    @inlinable
    public init(seq: Int, event: String, body: DAPJSONValue? = nil) {
        self.seq = seq
        self.type = .event
        self.event = event
        self.body = body
    }
}

// MARK: - Sum type

/// Polymorphic envelope for any DAP message shape.
/// Codable uses a single “type” discriminator for compact JSON.
@frozen
public enum DAPMessage: Sendable {
    case request(DAPRequest)
    case response(DAPResponse)
    case event(DAPEvent)

    /// Monotonic sequence number for the outer message.
    @inlinable
    public var seq: Int {
        switch self {
        case .request(let r): return r.seq
        case .response(let r): return r.seq
        case .event(let e): return e.seq
        }
    }

    /// Convenience view of the discriminator.
    @inlinable
    public var type: DAPMessageType {
        switch self {
        case .request: return .request
        case .response: return .response
        case .event: return .event
        }
    }
}

// MARK: - Codable (single-discriminator)

extension DAPMessage: Codable {
    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        switch try box.decode(DAPMessageType.self, forKey: .type) {
        case .request: self = .request(try DAPRequest(from: decoder))
        case .response: self = .response(try DAPResponse(from: decoder))
        case .event: self = .event(try DAPEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let r): try r.encode(to: encoder)
        case .response(let r): try r.encode(to: encoder)
        case .event(let e): try e.encode(to: encoder)
        }
    }
}

// MARK: - Low-overhead typed body/arguments decoding

extension DAPRequest {
    /// Decodes `arguments` into a concrete `Decodable` with minimal overhead.
    /// Uses `JSONSerialization` bridge to avoid reflection on intermediate wrapper types.
    @inlinable
    public func decodeArguments<T: Decodable>(
        as _: T.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let args = arguments else {
            throw DAPError.invalidMessage(
                "Request '\(command)' has no arguments"
            )
        }
        let data = try args.data()
        return try decoder.decode(T.self, from: data)
    }
}

extension DAPResponse {
    /// Decodes `body` into a concrete `Decodable` with minimal overhead.
    @inlinable
    public func decodeBody<T: Decodable>(
        as _: T.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let b = body else {
            throw DAPError.invalidResponse("Response '\(command)' has no body")
        }
        let data = try b.data()
        return try decoder.decode(T.self, from: data)
    }
}

extension DAPEvent {
    /// Decodes event `body` into a concrete `Decodable` with minimal overhead.
    @inlinable
    public func decodeBody<T: Decodable>(
        as _: T.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let b = body else {
            throw DAPError.invalidMessage("Event '\(event)' has no body")
        }
        let data = try b.data()
        return try decoder.decode(T.self, from: data)
    }
}
