//
//  DAPAdapter.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Role: Domain/Debugger
//  Deps: DAPSession, DAPAdapterManifest, DAPConfigurationManager, DAPSessionStore
//
//  Purpose:
//  --------
//  Defines the SPI for concrete DAP adapters and a small base class with
//  lifecycle utilities (prepare/start/stop/resume). The base class handles
//  common persistence + logging, while leaving process/transport decisions
//  to subclasses.
//

import Foundation

// MARK: - Adapter Protocol

public protocol DAPAdapter: AnyObject, Sendable {
    var manifest: DAPAdapterManifest { get }
    var session: DAPSession? { get }

    /// Build a new session but do not start it yet.
    func prepareSession(configuration: [String: DAPJSONValue]) throws
        -> DAPSession

    /// Start the current `session` (must be set by `prepareSession`).
    func startSession() async throws

    /// Stop the current `session` if active (idempotent).
    func stopSession() async

    /// Recreate and start a session from persisted metadata.
    func resumeSession(from metadata: DAPSessionMetadata) async throws
}

// MARK: - Zero-cost Defaults

extension DAPAdapter {
    @inlinable
    public func stopSession() async {}

    @inlinable
    public func resumeSession(from metadata: DAPSessionMetadata) async throws {
        throw DAPError.unsupportedFeature(
            "Adapter does not support resuming sessions."
        )
    }
}

// MARK: - Context

/// Carries shared services to adapters. Reference type to avoid copying.
/// Conformance is unchecked due to reference-typed collaborators.
public final class DAPAdapterContext: @unchecked Sendable {
    public let configurationManager: DAPConfigurationManager
    public let registry: DAPAdapterRegistry
    public let sessionStore: DAPSessionStore

    public init(
        configurationManager: DAPConfigurationManager,
        registry: DAPAdapterRegistry,
        sessionStore: DAPSessionStore
    ) {
        self.configurationManager = configurationManager
        self.registry = registry
        self.sessionStore = sessionStore
    }
}

// MARK: - Base Class

open class BaseDAPAdapter: DAPAdapter, @unchecked Sendable {
    public let manifest: DAPAdapterManifest
    public internal(set) var session: DAPSession?

    internal let context: DAPAdapterContext
    internal let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "BaseDAPAdapter"
    )

    public init(manifest: DAPAdapterManifest, context: DAPAdapterContext) {
        self.manifest = manifest
        self.context = context
    }

    // Subclasses must create the DAPSession (not started).
    open func prepareSession(configuration: [String: DAPJSONValue]) throws
        -> DAPSession
    {
        preconditionFailure(
            "Subclasses must override prepareSession(configuration:)"
        )
    }

    /// Starts the prepared session and persists it. Guarded to avoid double-starts.
    open func startSession() async throws {
        guard let session else {
            throw DAPError.sessionNotActive
        }

        // If the session object tracks state, avoid redundant starts.
        // (Safe even if `start()` is idempotent.)
        logger.debug(
            "Starting DAP session \(session.identifier) [\(manifest.identifier)]"
        )
        try await session.start()
        context.sessionStore.persistSession(session)
        logger.log(
            "DAP session started \(session.identifier) [\(manifest.identifier)]"
        )
    }

    /// Stops the session (if any), removes persisted state, and clears the handle.
    open func stopSession() async {
        guard let session else { return }
        logger.debug(
            "Stopping DAP session \(session.identifier) [\(manifest.identifier)]"
        )
        await session.stop()
        context.sessionStore.removeSession(with: session.identifier)
        self.session = nil
        logger.log("DAP session stopped [\(manifest.identifier)]")
    }

    /// Rebuilds a session from metadata, then starts it.
    open func resumeSession(from metadata: DAPSessionMetadata) async throws {
        logger.debug(
            "Resuming DAP session from metadata [\(manifest.identifier)]"
        )
        let resumed = try prepareSession(configuration: metadata.configuration)
        self.session = resumed
        try await startSession()
        logger.log(
            "DAP session resumed \(resumed.identifier) [\(manifest.identifier)]"
        )
    }
}
