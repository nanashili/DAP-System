//
//  DAPError.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

public enum DAPError: Error, LocalizedError, Sendable {
    case invalidMessage(String)
    case transportFailure(String)
    case configurationNotFound(String)
    case configurationInvalid(String)
    case adapterUnavailable(String)
    case processLaunchFailed(String)
    case sessionNotActive
    case persistenceFailure(String)
    case unsupportedFeature(String)
    case invalidResponse(String)

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
