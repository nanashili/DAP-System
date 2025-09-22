//
//  DAPAdapterRegistry.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  Actor-backed registry for Debug Adapter Protocol (DAP) adapters.
//  - Loads & tracks adapter manifests from configuration sources.
//  - Exposes a small factory system keyed by runtime identifiers.
//  - Notifies a main-actor delegate when the available adapters change.
//

import Foundation

public typealias DAPAdapterFactory =
    @Sendable (DAPAdapterManifest, DAPAdapterContext) -> DAPAdapter

public protocol DAPAdapterRegistryDelegate: AnyObject {
    func adapterRegistry(
        _ registry: DAPAdapterRegistry,
        didUpdateAvailableAdapters adapters: [DAPAdapterManifest]
    )
}

@MainActor
public protocol DAPAdapterRegistryUIDelegate: AnyObject {
    func adapterRegistryDidUpdate(_ adapters: [DAPAdapterManifest])
}

public actor DAPAdapterRegistry {
    // MARK: - Logging
    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPAdapterRegistry"
    )

    // MARK: - State (actor-isolated)
    private var factories: [String: DAPAdapterFactory] = [:]
    private var manifests: [DAPAdapterManifest] = []

    // MARK: - Collaborators
    private let configurationManager: DAPConfigurationManager
    private let sessionStore: DAPSessionStore

    // Delegate is UI-facing; keep it on main actor for view bindings.
    @MainActor public weak var delegate: DAPAdapterRegistryDelegate?

    // MARK: - Init
    public init(
        configurationManager: DAPConfigurationManager,
        sessionStore: DAPSessionStore
    ) {
        self.configurationManager = configurationManager
        self.sessionStore = sessionStore
    }

    // MARK: - Bootstrap & Watching

    /// Registers built-ins and loads manifests once. Safe to call multiple times.
    public func bootstrap() {
        registerFactory(
            { manifest, context in
                ExternalProcessDAPAdapter(manifest: manifest, context: context)
            },
            for: .externalProcess
        )

        registerFactory(
            { manifest, context in
                KotlinAdapter(manifest: manifest, context: context)
            },
            for: .kotlin
        )

        // Initial load
        reloadManifests(reason: "bootstrap")

        configurationManager.watchForChanges { [weak self] newManifests in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                self.logger.debug(
                    "Manifest directory changed; refreshing adapters."
                )
                await self.updateManifests(
                    newManifests,
                    reason: "filesystem change"
                )
            }
        }
    }

    /// Manual refresh from disk/config source.
    public func reloadManifests() {
        reloadManifests(reason: "manual reload")
    }

    // MARK: - Public Queries

    /// Snapshot of current adapter manifests.
    public func availableAdapters() -> [DAPAdapterManifest] {
        manifests
    }

    /// Builds a concrete adapter instance for a given manifest.
    public func makeAdapter(for manifest: DAPAdapterManifest) throws
        -> DAPAdapter
    {
        let runtimeKey = manifest.runtime.rawValue
        let factory =
            factories[runtimeKey]
            ?? factories[DAPRuntimeIdentifier.externalProcess.rawValue]

        guard let factory else {
            throw DAPError.adapterUnavailable(
                "No factory registered for runtime \(runtimeKey)"
            )
        }

        let context = DAPAdapterContext(
            configurationManager: configurationManager,
            registry: self,
            sessionStore: sessionStore
        )
        return factory(manifest, context)
    }

    /// Exposes the shared session persistence store.
    public nonisolated func sessionPersistenceStore() -> DAPSessionStore {
        sessionStore
    }

    // MARK: - Factory Registration

    public func registerFactory(
        _ factory: @escaping DAPAdapterFactory,
        for runtime: DAPRuntimeIdentifier
    ) {
        factories[runtime.rawValue] = factory
    }

    public func registerFactory(
        _ factory: @escaping DAPAdapterFactory,
        forRuntimeString runtime: String
    ) {
        factories[runtime] = factory
    }

    // MARK: - Internal Loading Pipeline

    private func reloadManifests(reason: String) {
        do {
            let loaded = try configurationManager.loadManifests()
            Task { updateManifests(loaded, reason: reason) }
        } catch {
            logger.error(
                "Failed to load DAP manifests: \(error.localizedDescription)"
            )
        }
    }

    private func updateManifests(_ new: [DAPAdapterManifest], reason: String) {
        manifests = new
        logger.log("Adapters updated (\(new.count)) after \(reason).")
        notifyDelegate(with: new)
    }

    // MARK: - Delegate Dispatch

    private func notifyDelegate(with manifests: [DAPAdapterManifest]) {
        Task { @MainActor [weak self] in
            guard let self, let delegate else { return }
            delegate.adapterRegistry(
                self,
                didUpdateAvailableAdapters: manifests
            )
        }
    }
}
