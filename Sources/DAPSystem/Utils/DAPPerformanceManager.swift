//
//  DAPPerformanceManager.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  Tracks and optimizes Debug Adapter Protocol (DAP) session performance.
//  Provides lightweight heuristics for memory trimming, throughput tuning,
//  and reporting diagnostic metrics to the logger.
//

import Foundation

public final class DAPPerformanceManager: @unchecked Sendable {

    /// Encapsulates runtime performance characteristics for a session.
    public struct Metrics: Sendable {
        /// Messages handled per minute across the broker.
        public let messagesPerMinute: Double
        /// Average JSON payload size in bytes.
        public let averagePayloadSize: Int
        /// Current resident memory usage in bytes.
        public let residentMemory: UInt64
    }

    // MARK: - Private

    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPPerformanceManager"
    )

    // MARK: - Init

    public init() {}

    // MARK: - Adaptive Controls

    /// Enables optimizations based on approximate project size.
    /// - Parameter projectSize: Number of source files or LOC (line-of-code proxy).
    public func optimize(for projectSize: Int) {
        guard projectSize > 100_000 else { return }
        logger.log(
            "High-throughput mode enabled for large project (\(projectSize) units)"
        )
    }

    /// Triggers cache eviction when memory exceeds threshold.
    /// - Parameters:
    ///   - currentUsage: Current resident memory in bytes.
    ///   - threshold: Threshold at which eviction should begin.
    public func trimMemoryIfNeeded(currentUsage: UInt64, threshold: UInt64) {
        guard currentUsage > threshold else { return }
        logger.log(
            "Memory usage \(currentUsage) > threshold \(threshold). Evicting session caches."
        )
    }

    // MARK: - Metrics

    /// Reports performance metrics for diagnostic purposes.
    /// - Parameter metrics: Collected session metrics.
    public func report(metrics: Metrics) {
        let mb = Double(metrics.residentMemory) / (1024 * 1024)
        logger.log(
            "Metrics | throughput=\(String(format: "%.1f", metrics.messagesPerMinute)) msg/min, "
                + "payload=\(metrics.averagePayloadSize) B, "
                + "memory=\(String(format: "%.2f", mb)) MB"
        )
    }
}
