//
//  DAPSessionStore.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  - Atomically persists and loads DAP session metadata to disk.
//  - Handles recovery, removal, and backup directory management.
//  - Intended to be injected, not a global singleton.
//

import Foundation

public final class DAPSessionStore: @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: DAPLogger

    /// Designated initializer.
    /// - Parameter storageDirectory: Directory where sessions.json is written.
    public init(storageDirectory: URL) {
        self.fileManager = .default
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.logger = DAPLogger(
            subsystem: "com.valkarystudio.debugger",
            category: "DAPSessionStore"
        )
        self.storageURL = storageDirectory.appendingPathComponent(
            "sessions.json"
        )

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Ensure parent directory exists.
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: storageDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                logger.error(
                    "Failed to create session store directory: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Atomically persists or updates a session's metadata on disk.
    /// - Parameter session: The active DAPSession to persist.
    public func persistSession(_ session: DAPSession) {
        do {
            var sessions = try loadAllMetadata()
            let metadata = DAPSessionMetadata(
                sessionID: session.identifier,
                adapterIdentifier: session.manifest.identifier,
                openedFiles: [],  // TODO: implement file tracking
                timestamp: Date(),
                configuration: session.configuration
            )
            sessions.removeAll { $0.sessionID == session.identifier }
            sessions.append(metadata)
            try save(metadata: sessions)
        } catch {
            logger.error(
                "Unable to persist DAP session: \(error.localizedDescription)"
            )
        }
    }

    /// Removes a session record (if present) by UUID.
    public func removeSession(with identifier: UUID) {
        do {
            var sessions = try loadAllMetadata()
            let before = sessions.count
            sessions.removeAll { $0.sessionID == identifier }
            let after = sessions.count
            if before != after {
                try save(metadata: sessions)
            }
        } catch {
            logger.error(
                "Unable to remove DAP session metadata: \(error.localizedDescription)"
            )
        }
    }

    /// Loads all known session metadata from disk.
    /// - Returns: An array of DAPSessionMetadata. Returns [] if missing.
    public func loadAllMetadata() throws -> [DAPSessionMetadata] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([DAPSessionMetadata].self, from: data)
    }

    // MARK: - Internal Persistence

    /// Synchronously writes metadata to disk (atomic).
    private func save(metadata: [DAPSessionMetadata]) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: storageURL, options: [.atomic])
    }
}
