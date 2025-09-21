import XCTest

@testable import DAPSystem

final class ExternalProcessDAPAdapterTests: XCTestCase {
    func testEmptyManifestEnvironmentInheritsHostEnvironment() {
        let adapter = ExternalProcessDAPAdapter(
            manifest: makeManifest(environment: [:]),
            context: makeContext()
        )

        let hostEnvironment = ["PATH": "/usr/bin"]
        let resolved = adapter.resolvedEnvironment(
            hostEnvironment: hostEnvironment
        )

        XCTAssertFalse(
            resolved.isEmpty,
            "Resolved environment should not be empty when host env is provided"
        )
        XCTAssertEqual(resolved["PATH"], "/usr/bin")
    }

    func testManifestEnvironmentOverridesHostValues() {
        let adapter = ExternalProcessDAPAdapter(
            manifest: makeManifest(environment: [
                "PATH": "/custom/bin",
                "NEW_VAR": "VALUE",
            ]),
            context: makeContext()
        )

        let hostEnvironment = [
            "PATH": "/usr/bin",
            "UNCHANGED": "value",
        ]
        let resolved = adapter.resolvedEnvironment(
            hostEnvironment: hostEnvironment
        )

        XCTAssertEqual(resolved["PATH"], "/custom/bin")
        XCTAssertEqual(resolved["NEW_VAR"], "VALUE")
        XCTAssertEqual(resolved["UNCHANGED"], "value")
    }

    // MARK: - Helpers

    private func makeManifest(environment: [String: String])
        -> DAPAdapterManifest
    {
        DAPAdapterManifest(
            identifier: "com.valkarystudio.test",
            displayName: "Test Adapter",
            version: "1.0.0",
            runtime: .externalProcess,
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: nil,
            environment: environment,
            languages: ["test"],
            capabilities: [],
            configurationFields: [],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: false
        )
    }

    private func makeContext() -> DAPAdapterContext {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
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

        return DAPAdapterContext(
            configurationManager: configurationManager,
            registry: registry,
            sessionStore: sessionStore
        )
    }
}
