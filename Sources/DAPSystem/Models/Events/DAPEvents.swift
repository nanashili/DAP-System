//
//  DAPStoppedEvent.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public enum DAPSessionEvent: Sendable, Equatable {
    case initialized
    case stopped(DAPStoppedEvent)
    case continued(DAPContinuedEvent)
    case terminated(DAPTerminatedEvent)
    case output(DAPOutputEvent)
}

@frozen
public struct DAPStoppedEvent: Sendable, Equatable {
    public let reason: String
    public let description: String?
    public let threadId: Int?
    public let text: String?
    public let allThreadsStopped: Bool?

    @inlinable
    public init(
        reason: String,
        description: String?,
        threadId: Int?,
        text: String?,
        allThreadsStopped: Bool?
    ) {
        self.reason = reason
        self.description = description
        self.threadId = threadId
        self.text = text
        self.allThreadsStopped = allThreadsStopped
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let reason = o[_J.reason]?.stringValue
        else {
            throw DAPError.invalidResponse("Stopped event missing reason")
        }
        self.init(
            reason: reason,
            description: o[_J.description]?.stringValue,
            threadId: o[_J.threadId]?.intValue,
            text: o[_J.text]?.stringValue,
            allThreadsStopped: o[_J.allThreadsStopped]?.boolValue
        )
    }
}

@frozen
public struct DAPContinuedEvent: Sendable, Equatable {
    public let threadId: Int?
    public let allThreadsContinued: Bool?

    @inlinable
    public init(threadId: Int?, allThreadsContinued: Bool?) {
        self.threadId = threadId
        self.allThreadsContinued = allThreadsContinued
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json else {
            throw DAPError.invalidResponse(
                "Continued event must include an object body"
            )
        }
        self.init(
            threadId: o[_J.threadId]?.intValue,
            allThreadsContinued: o[_J.allThreadsContinued]?.boolValue
        )
    }
}

@frozen
public struct DAPTerminatedEvent: Sendable, Equatable {
    public let restart: Bool?

    @inlinable
    public init(restart: Bool?) { self.restart = restart }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json else {
            throw DAPError.invalidResponse(
                "Terminated event must include an object body"
            )
        }
        self.init(restart: o[_J.restart]?.boolValue)
    }
}

@frozen
public struct DAPOutputEvent: Sendable, Equatable {
    /// Adapter-defined category (e.g., "console", "stderr", "stdout", "telemetry").
    public let category: String?
    /// The text to show to the user; required by spec.
    public let output: String
    /// Variables reference for structured payloads (optional).
    public let variablesReference: Int?
    /// Additional rich data (adapter-defined). Optional.
    public let data: [String: DAPJSONValue]?

    @inlinable
    public init(
        category: String?,
        output: String,
        variablesReference: Int?,
        data: [String: DAPJSONValue]?
    ) {
        self.category = category
        self.output = output
        self.variablesReference = variablesReference
        self.data = data
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let out = o[_J.output]?.stringValue
        else {
            throw DAPError.invalidResponse("Output event missing output text")
        }
        self.init(
            category: o[_J.category]?.stringValue,
            output: out,
            variablesReference: o[_J.variablesReference]?.intValue,
            data: o[_J.data]?.objectValue
        )
    }
}
