//
//  DAPRecoverableSession.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  - Value type describing a persisted session that can be resumed.
//  - Main-actor coordinator that owns adapters bound to UI lifecycle.
//  - Bridges actor-backed registry to UI safely, keeps state minimal & explicit.
//

import AppKit
import Foundation

// MARK: - Model

public struct DAPRecoverableSession: Identifiable, Sendable, Equatable {
    public let metadata: DAPSessionMetadata
    public let manifest: DAPAdapterManifest

    @inlinable
    public var id: UUID { metadata.sessionID }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.metadata == rhs.metadata
            && lhs.manifest.identifier == rhs.manifest.identifier
    }
}

// MARK: - Coordinator

/// Orchestrates DAP adapter sessions and UI recovery on the main actor.
/// Not thread-safe—call only from main/UI thread.
@MainActor
public final class DAPDebuggerCoordinator {
    private let registry: DAPAdapterRegistry
    private let sessionStore: DAPSessionStore
    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPDebuggerCoordinator"
    )

    // Active DAPAdapters keyed by session UUID.
    private var activeAdapters: [UUID: DAPAdapter] = [:]
    // Current recoverable sessions, for UI binding or inspection.
    public private(set) var recoverableSessions: [DAPRecoverableSession] = []

    // MARK: - Init

    public init(
        registry: DAPAdapterRegistry,
        sessionStore: DAPSessionStore? = nil
    ) {
        self.registry = registry
        self.sessionStore = sessionStore ?? registry.sessionPersistenceStore()
        Task { await reloadRecoverableSessions() }
    }

    // MARK: - Adapter Selection

    /// Lists all adapters for the picker UI.
    public func presentAdapterSelection(from viewController: NSViewController)
        async -> [DAPAdapterManifest]
    {
        let adapters = await registry.availableAdapters()
        logger.log(
            "Presenting adapter selection with \(adapters.count) options."
        )
        return adapters
    }

    // MARK: - Session Lifecycle

    /// Prepare, start, and persist a debug session. If start fails, rolls back cleanly.
    public func startSession(
        with manifest: DAPAdapterManifest,
        configuration: [String: DAPJSONValue]
    ) async {
        do {
            let adapter = try await registry.makeAdapter(for: manifest)
            let session = try adapter.prepareSession(
                configuration: configuration
            )
            activeAdapters[session.identifier] = adapter

            do {
                try await adapter.startSession()
            } catch {
                _ = activeAdapters.removeValue(forKey: session.identifier)
                throw error
            }
            await reloadRecoverableSessions()
        } catch {
            logger.error(
                "Failed to start session: \(error.localizedDescription)"
            )
        }
    }

    /// Stops and forgets a single session, if active.
    public func stopSession(_ sessionID: UUID) async {
        guard let adapter = activeAdapters.removeValue(forKey: sessionID) else {
            return
        }
        await adapter.stopSession()
        await reloadRecoverableSessions()
    }

    /// Stops all sessions concurrently.
    public func stopAllSessions() async {
        let entries = activeAdapters
        activeAdapters.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for (_, adapter) in entries {
                group.addTask { await adapter.stopSession() }
            }
            await group.waitForAll()
        }
        await reloadRecoverableSessions()
    }

    // MARK: - Persistence & Recovery

    /// Reloads recoverable sessions from store + current adapter registry, sorted newest first.
    public func reloadRecoverableSessions() async {
        do {
            let metadata = try sessionStore.loadAllMetadata()
            let manifests = await registry.availableAdapters()
            let byID = Dictionary(
                uniqueKeysWithValues: manifests.map { ($0.identifier, $0) }
            )
            let activeIDs = Set(activeAdapters.keys)

            recoverableSessions =
                metadata
                .compactMap { entry in
                    guard !activeIDs.contains(entry.sessionID),
                        let manifest = byID[entry.adapterIdentifier],
                        manifest.supportsPersistence
                    else { return nil }
                    return DAPRecoverableSession(
                        metadata: entry,
                        manifest: manifest
                    )
                }
                .sorted { $0.metadata.timestamp > $1.metadata.timestamp }
        } catch {
            recoverableSessions = []
            logger.error(
                "Failed to load persisted sessions: \(error.localizedDescription)"
            )
        }
    }

    /// Resumes a persisted session by metadata (removes old record if unsupported or after resumption).
    public func resumePersistedSession(_ metadata: DAPSessionMetadata) async {
        let manifests = await registry.availableAdapters()
        guard
            let manifest = manifests.first(where: {
                $0.identifier == metadata.adapterIdentifier
            })
        else {
            logger.error(
                "No manifest available for persisted session \(metadata.sessionID)"
            )
            return
        }

        guard manifest.supportsPersistence else {
            logger.error(
                "Manifest \(manifest.identifier) does not support persistence; cannot resume \(metadata.sessionID)"
            )
            sessionStore.removeSession(with: metadata.sessionID)
            await reloadRecoverableSessions()
            return
        }

        do {
            let adapter = try await registry.makeAdapter(for: manifest)
            try await adapter.resumeSession(from: metadata)
            if let session = adapter.session {
                activeAdapters[session.identifier] = adapter
            }
            sessionStore.removeSession(with: metadata.sessionID)
            await reloadRecoverableSessions()
        } catch {
            logger.error(
                "Failed to resume persisted session \(metadata.sessionID): \(error.localizedDescription)"
            )
        }
    }

    /// Deletes a persisted session record without resuming it.
    public func discardPersistedSession(_ sessionID: UUID) async {
        sessionStore.removeSession(with: sessionID)
        await reloadRecoverableSessions()
    }

    // MARK: - Utilities

    /// Number of currently running debug sessions.
    public var activeCount: Int { activeAdapters.count }

    /// Returns true if the given session UUID is currently running.
    public func isActive(_ id: UUID) -> Bool { activeAdapters[id] != nil }
}
