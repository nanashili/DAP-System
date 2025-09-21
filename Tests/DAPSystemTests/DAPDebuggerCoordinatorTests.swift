//
//  DAPDebuggerCoordinatorTests.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import XCTest

@testable import DAPSystem

@MainActor
final class DAPDebuggerCoordinatorTests: XCTestCase {
    func testRecoverableSessionsLifecycle() async throws {
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

        let manifest = makePersistableManifest()
        try write(manifest: manifest, to: manifestsDirectory)

        let configurationManager = DAPConfigurationManager(
            manifestsDirectory: manifestsDirectory
        )
        let sessionStore = DAPSessionStore(storageDirectory: sessionsDirectory)
        let registry = DAPAdapterRegistry(
            configurationManager: configurationManager,
            sessionStore: sessionStore
        )

        // Register test factory (actor API)
        await registry.registerFactory(
            { manifest, context in
                TestRecoveringAdapter(manifest: manifest, context: context)
            },
            forRuntimeString: manifest.runtime.rawValue
        )

        await registry.bootstrap()

        // Coordinator runs on main actor
        let coordinator = DAPDebuggerCoordinator(
            registry: registry,
            sessionStore: sessionStore
        )

        XCTAssertTrue(coordinator.recoverableSessions.isEmpty)

        // Persist a session (should become recoverable)
        let session = makeSession(for: manifest)
        sessionStore.persistSession(session)

        await coordinator.reloadRecoverableSessions()
        XCTAssertEqual(coordinator.recoverableSessions.count, 1)
        let recoverable = try XCTUnwrap(coordinator.recoverableSessions.first)
        XCTAssertEqual(recoverable.manifest.identifier, manifest.identifier)
        XCTAssertEqual(
            recoverable.metadata.configuration["program"],
            .string("/tmp/program")
        )

        TestRecoveringAdapter.reset()
        await coordinator.resumePersistedSession(recoverable.metadata)

        let adapter = try XCTUnwrap(TestRecoveringAdapter.lastInstance)
        XCTAssertEqual(
            adapter.resumeMetadata?.sessionID,
            recoverable.metadata.sessionID
        )
        XCTAssertEqual(
            adapter.resumeMetadata?.configuration["program"],
            .string("/tmp/program")
        )

        // Should have been removed from persistence after resume
        let remainingMetadata = try sessionStore.loadAllMetadata()
        XCTAssertFalse(
            remainingMetadata.contains(where: {
                $0.sessionID == recoverable.metadata.sessionID
            })
        )

        await coordinator.reloadRecoverableSessions()
        XCTAssertTrue(coordinator.recoverableSessions.isEmpty)

        // Add and discard a new session
        let newSession = makeSession(for: manifest)
        sessionStore.persistSession(newSession)
        await coordinator.reloadRecoverableSessions()
        XCTAssertEqual(coordinator.recoverableSessions.count, 1)

        await coordinator.discardPersistedSession(newSession.identifier)
        let metadataAfterDiscard = try sessionStore.loadAllMetadata()
        XCTAssertFalse(
            metadataAfterDiscard.contains {
                $0.sessionID == newSession.identifier
            }
        )
        XCTAssertTrue(coordinator.recoverableSessions.isEmpty)
    }

    // MARK: - Helpers

    private func makePersistableManifest() -> DAPAdapterManifest {
        DAPAdapterManifest(
            identifier: "test.persistence",
            displayName: "Persistence Adapter",
            version: "1.0.0",
            runtime: DAPRuntimeIdentifier("test.runtime"),
            executable: "/usr/bin/env",
            arguments: ["bash"],
            workingDirectory: nil,
            environment: [:],
            languages: ["swift"],
            capabilities: [],
            configurationFields: [
                DAPAdapterConfigurationField(
                    key: "program",
                    title: "Program",
                    type: .text,
                    defaultValue: nil,
                    description: "Path to the program to debug"
                )
            ],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: true
        )
    }

    private func makeSession(for manifest: DAPAdapterManifest) -> DAPSession {
        let configuration: [String: DAPJSONValue] = [
            "request": .string("launch"),
            "program": .string("/tmp/program"),
        ]

        let transport = NullTransport()
        let broker = DAPMessageBroker(transport: transport)
        return DAPSession(
            manifest: manifest,
            configuration: configuration,
            broker: broker
        )
    }

    private func write(manifest: DAPAdapterManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([manifest])
        let url = directory.appendingPathComponent("manifest.json")
        try data.write(to: url, options: .atomic)
    }
}

// -- TestRecoveringAdapter & NullTransport unchanged (use your original definitions)
private final class TestRecoveringAdapter: BaseDAPAdapter, @unchecked Sendable {
    static private(set) var lastInstance: TestRecoveringAdapter?
    private(set) var resumeMetadata: DAPSessionMetadata?

    override init(manifest: DAPAdapterManifest, context: DAPAdapterContext) {
        super.init(manifest: manifest, context: context)
        TestRecoveringAdapter.lastInstance = self
    }

    override func prepareSession(configuration: [String: DAPJSONValue]) throws
        -> DAPSession
    {
        let broker = DAPMessageBroker(transport: NullTransport())
        let session = DAPSession(
            manifest: manifest,
            configuration: configuration,
            broker: broker
        )
        self.session = session
        return session
    }

    override func startSession() async throws {
        guard let session else { throw DAPError.sessionNotActive }
        context.sessionStore.persistSession(session)
    }

    override func resumeSession(from metadata: DAPSessionMetadata) async throws
    {
        resumeMetadata = metadata
        let session = try prepareSession(configuration: metadata.configuration)
        self.session = session
        context.sessionStore.persistSession(session)
    }

    override func stopSession() async {
        guard let session else { return }
        context.sessionStore.removeSession(with: session.identifier)
        self.session = nil
    }

    static func reset() {
        lastInstance = nil
    }
}

private final class NullTransport: DAPTransport {
    func startReceiving(
        _ handler: @escaping @Sendable (Result<DAPMessage, DAPError>) -> Void
    ) {}
    func send(_ message: DAPMessage) throws {}
    func close() {}
}
