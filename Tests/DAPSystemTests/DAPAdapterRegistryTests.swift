//
//  DAPAdapterRegistryTests.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import XCTest

@testable import DAPSystem

final class DAPAdapterRegistryTests: XCTestCase {
    // Must be async for modern actor-based API
    func testManifestReloadNotifiesDelegate() async throws {
        let fileManager = FileManager.default
        let manifestsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: manifestsDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: manifestsDirectory) }

        let sessionsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: sessionsDirectory) }

        let manifestURL = manifestsDirectory.appendingPathComponent(
            "manifest.json"
        )
        let initialManifest = DAPAdapterManifest(
            identifier: "test.adapter",
            displayName: "Test Adapter",
            version: "1.0.0",
            runtime: .externalProcess,
            executable: "/usr/bin/env",
            arguments: ["bash"],
            workingDirectory: nil,
            environment: [:],
            languages: ["swift"],
            capabilities: [],
            configurationFields: [],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: false
        )
        try write(manifests: [initialManifest], to: manifestURL)

        let configurationManager = DAPConfigurationManager(
            manifestsDirectory: manifestsDirectory
        )
        let sessionStore = DAPSessionStore(storageDirectory: sessionsDirectory)
        let registry = DAPAdapterRegistry(
            configurationManager: configurationManager,
            sessionStore: sessionStore
        )

        // MARK: - Delegate
        final class Delegate: DAPAdapterRegistryDelegate {
            let initialExpectation: XCTestExpectation
            let updateExpectation: XCTestExpectation
            let initialCount: Int
            var receivedInitial = false
            var receivedUpdate = false

            init(
                initialExpectation: XCTestExpectation,
                updateExpectation: XCTestExpectation,
                initialCount: Int
            ) {
                self.initialExpectation = initialExpectation
                self.updateExpectation = updateExpectation
                self.initialCount = initialCount
            }

            func adapterRegistry(
                _ registry: DAPAdapterRegistry,
                didUpdateAvailableAdapters adapters: [DAPAdapterManifest]
            ) {
                if !receivedInitial, adapters.count == initialCount {
                    receivedInitial = true
                    initialExpectation.fulfill()
                } else if !receivedUpdate, adapters.count == initialCount + 1 {
                    receivedUpdate = true
                    updateExpectation.fulfill()
                }
            }
        }

        let initialExpectation = expectation(
            description: "Initial manifests loaded"
        )
        let updateExpectation = expectation(
            description: "Manifest update delivered"
        )

        let delegate = Delegate(
            initialExpectation: initialExpectation,
            updateExpectation: updateExpectation,
            initialCount: 1
        )

        // Set delegate on the main actor
        await MainActor.run {
            registry.delegate = delegate
        }
        await registry.bootstrap()

        // Wait for initial expectation
        await fulfillment(of: [initialExpectation], timeout: 2.0)

        // Simulate file system change (always prefer Task.sleep for async)
        try await Task.sleep(nanoseconds: 150_000_000)  // 150ms

        let updatedManifest = DAPAdapterManifest(
            identifier: "test.adapter.updated",
            displayName: "Test Adapter Updated",
            version: "2.0.0",
            runtime: .externalProcess,
            executable: "/usr/bin/env",
            arguments: ["bash"],
            workingDirectory: nil,
            environment: [:],
            languages: ["swift"],
            capabilities: [],
            configurationFields: [],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: false
        )
        try write(
            manifests: [initialManifest, updatedManifest],
            to: manifestURL
        )

        await fulfillment(of: [updateExpectation], timeout: 2.0)
    }

    private func write(manifests: [DAPAdapterManifest], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifests)
        try data.write(to: url, options: .atomic)
    }
}
