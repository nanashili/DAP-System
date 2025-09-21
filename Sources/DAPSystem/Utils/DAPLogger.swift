//
//  DAPLogger.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  Lightweight wrapper around Apple's unified logging system (`OSLog`).
//  Provides structured, privacy-aware logging with category scoping.
//  Designed for Debug Adapter Protocol (DAP) subsystems.
//

import Foundation
import OSLog

public struct DAPLogger: Sendable {
    private let logger: Logger

    /// Creates a new logger for a given subsystem and category.
    /// - Parameters:
    ///   - subsystem: Usually the bundle identifier or module namespace.
    ///   - category: Component within the subsystem (e.g., "PerformanceManager").
    public init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Public API

    /// Logs a general info-level message.
    public func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
    }

    /// Logs a debug-level message (hidden in production unless explicitly enabled).
    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Logs a warning message.
    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    /// Logs an error message.
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Logs a critical failure message.
    public func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}
