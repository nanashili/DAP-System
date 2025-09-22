//
//  DAPError.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

/// Canonical error type for the Valkary Studio DAP system.
/// All runtime and adapter errors should be funneled through this enum
/// for predictable handling and logging.
@frozen
public enum DAPError: Error, LocalizedError, Sendable {

    /// Malformed or incomplete DAP message from an adapter or client.
    case invalidMessage(String)

    /// Transport channel failure (e.g., pipe/socket closed unexpectedly).
    case transportFailure(String)

    /// Referenced configuration identifier not found in workspace/project.
    case configurationNotFound(String)

    /// Configuration exists but is structurally invalid or missing required fields.
    case configurationInvalid(String)

    /// Debug adapter is not registered, not installed, or cannot be resolved.
    case adapterUnavailable(String)

    /// Failure to launch the adapter process (e.g., missing binary, spawn error).
    case processLaunchFailed(String)

    /// Operation requires an active debug session, but none is active.
    case sessionNotActive

    /// Failure to persist or restore session state (e.g., workspace storage error).
    case persistenceFailure(String)

    /// Feature requested by the client is not implemented by the adapter.
    case unsupportedFeature(String)

    /// Response received from adapter is structurally invalid or missing required fields.
    case invalidResponse(String)
}

// MARK: - LocalizedError

extension DAPError {
    /// Developer- and user-facing descriptions.
    public var errorDescription: String? {
        switch self {
        case .invalidMessage(let reason):
            return "Invalid DAP message: \(reason)"
        case .transportFailure(let reason):
            return "Transport error: \(reason)"
        case .configurationNotFound(let identifier):
            return "No configuration found for adapter \(identifier)."
        case .configurationInvalid(let reason):
            return "Configuration validation failed: \(reason)"
        case .adapterUnavailable(let identifier):
            return "Adapter \(identifier) is not currently available."
        case .processLaunchFailed(let reason):
            return "Unable to launch adapter process: \(reason)"
        case .sessionNotActive:
            return "Debug session is not active."
        case .persistenceFailure(let reason):
            return "Failed to persist debug session: \(reason)"
        case .unsupportedFeature(let reason):
            return "The requested feature is not supported: \(reason)"
        case .invalidResponse(let reason):
            return "Adapter returned an invalid response: \(reason)"
        }
    }
}
