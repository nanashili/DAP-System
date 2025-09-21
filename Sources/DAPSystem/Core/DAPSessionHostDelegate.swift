//
//  DAPSessionHostDelegate.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

/// Defines callbacks that allow a host application to service reverse requests
/// initiated by a debug adapter. The delegate is invoked on the broker's
/// internal executor, so callers should hop to an appropriate context before
/// touching UI or other main-thread-only resources.
public protocol DAPSessionHostDelegate: Sendable {
    /// Handles a `runInTerminal` request from the adapter. Implementations
    /// should launch the requested command and return any known process IDs.
    func session(
        _ session: DAPSession,
        runInTerminal request: DAPRunInTerminalRequest
    ) async throws -> DAPRunInTerminalResult

    /// Handles a `startDebugging` request from the adapter. Implementations
    /// should spin up a new debugging session using the supplied configuration
    /// and return an optional payload to include in the adapter response.
    func session(
        _ session: DAPSession,
        startDebugging request: DAPStartDebuggingRequest
    ) async throws -> DAPStartDebuggingResult
}

/// Captures the parameters of a `runInTerminal` request.
public struct DAPRunInTerminalRequest: Sendable, Equatable {
    public let kind: String?
    public let title: String?
    public let cwd: String?
    public let args: [String]
    public let env: [String: String]?
    public let envFile: String?

    public init(
        kind: String?,
        title: String?,
        cwd: String?,
        args: [String],
        env: [String: String]?,
        envFile: String?
    ) {
        self.kind = kind
        self.title = title
        self.cwd = cwd
        self.args = args
        self.env = env
        self.envFile = envFile
    }

    init(arguments: DAPJSONValue?) throws {
        guard case .object(let object) = arguments else {
            throw DAPError.invalidMessage(
                "runInTerminal arguments must be an object"
            )
        }

        guard
            let args = object["args"]?.arrayValue?.compactMap({ $0.stringValue }
            ),
            !args.isEmpty
        else {
            throw DAPError.invalidMessage(
                "runInTerminal args array is required"
            )
        }

        let cwd = object["cwd"]?.stringValue
        let envFile = object["envFile"]?.stringValue
        let kind = object["kind"]?.stringValue
        let title = object["title"]?.stringValue

        var environment: [String: String]?
        if let envObject = object["env"]?.objectValue {
            environment = [:]
            for (key, value) in envObject {
                if let stringValue = value.stringValue {
                    environment?[key] = stringValue
                }
            }
        }

        self.init(
            kind: kind,
            title: title,
            cwd: cwd,
            args: args,
            env: environment,
            envFile: envFile
        )
    }
}

/// Response payload for `runInTerminal`.
public struct DAPRunInTerminalResult: Sendable, Equatable {
    public let processId: Int?
    public let shellProcessId: Int?

    public init(processId: Int? = nil, shellProcessId: Int? = nil) {
        self.processId = processId
        self.shellProcessId = shellProcessId
    }

    var body: DAPJSONValue? {
        var object: [String: DAPJSONValue] = [:]
        if let processId {
            object["processId"] = .number(Double(processId))
        }
        if let shellProcessId {
            object["shellProcessId"] = .number(Double(shellProcessId))
        }
        return object.isEmpty ? nil : .object(object)
    }
}

/// Captures the parameters of a `startDebugging` request.
public struct DAPStartDebuggingRequest: Sendable, Equatable {
    public let request: String?
    public let configuration: [String: DAPJSONValue]
    public let arguments: [String: DAPJSONValue]

    public init(
        request: String?,
        configuration: [String: DAPJSONValue],
        arguments: [String: DAPJSONValue]
    ) {
        self.request = request
        self.configuration = configuration
        self.arguments = arguments
    }

    init(arguments value: DAPJSONValue?) throws {
        guard case .object(let object) = value else {
            throw DAPError.invalidMessage(
                "startDebugging arguments must be an object"
            )
        }

        guard case .object(let configuration)? = object["configuration"] else {
            throw DAPError.invalidMessage(
                "startDebugging configuration is required"
            )
        }

        let request = object["request"]?.stringValue

        self.init(
            request: request,
            configuration: configuration,
            arguments: object
        )
    }
}

/// Response payload for `startDebugging`.
public struct DAPStartDebuggingResult: Sendable, Equatable {
    public let body: DAPJSONValue?

    public init(body: DAPJSONValue? = nil) {
        self.body = body
    }
}

extension DAPSessionHostDelegate {
    public func session(
        _ session: DAPSession,
        runInTerminal request: DAPRunInTerminalRequest
    ) async throws -> DAPRunInTerminalResult {
        throw DAPError.unsupportedFeature(
            "runInTerminal is not supported by the current host"
        )
    }

    public func session(
        _ session: DAPSession,
        startDebugging request: DAPStartDebuggingRequest
    ) async throws -> DAPStartDebuggingResult {
        throw DAPError.unsupportedFeature(
            "startDebugging is not supported by the current host"
        )
    }
}
