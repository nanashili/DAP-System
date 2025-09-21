//
//  DAPRuntimeIdentifierTests.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import XCTest

@testable import DAPSystem

final class DAPRuntimeIdentifierTests: XCTestCase {
    func testDecodingPreservesUnknownRuntimeString() throws {
        let json = """
            [{
                "identifier": "com.valkarystudio.test",
                "displayName": "Test Adapter",
                "version": "1.0.0",
                "runtime": "mystery",
                "executable": "/usr/bin/true",
                "arguments": [],
                "workingDirectory": null,
                "environment": {},
                "languages": ["test"],
                "capabilities": [],
                "configurationFields": [],
                "supportsConditionalBreakpoints": false,
                "supportsWatchExpressions": false,
                "supportsPersistence": false
            }]
            """.data(using: .utf8)!

        let manifests = try JSONDecoder().decode(
            [DAPAdapterManifest].self,
            from: json
        )
        XCTAssertEqual(manifests.first?.runtime.rawValue, "mystery")
    }

    func testRegistryFallsBackToExternalProcessFactoryForUnknownRuntime()
        async throws
    {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        let configurationManager = DAPConfigurationManager(
            manifestsDirectory: tempDirectory
        )
        let sessionStore = DAPSessionStore(storageDirectory: tempDirectory)
        let registry = DAPAdapterRegistry(
            configurationManager: configurationManager,
            sessionStore: sessionStore
        )

        await registry.bootstrap()

        let manifest = DAPAdapterManifest(
            identifier: "com.valkarystudio.test",
            displayName: "Test Adapter",
            version: "1.0.0",
            runtime: DAPRuntimeIdentifier("totally-new-runtime"),
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: nil,
            environment: [:],
            languages: ["test"],
            capabilities: [],
            configurationFields: [],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: false
        )

        let adapter = try await registry.makeAdapter(for: manifest)
        XCTAssertTrue(adapter is ExternalProcessDAPAdapter)
    }
}
