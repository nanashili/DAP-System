import XCTest

@testable import DAPSystem

final class DAPSessionStoreTests: XCTestCase {
    func testPersistSessionCreatesStorageDirectory() throws {
        let fileManager = FileManager.default
        let temporaryBase = fileManager.temporaryDirectory
        let storageDirectory = temporaryBase.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? fileManager.removeItem(at: storageDirectory) }

        let store = DAPSessionStore(storageDirectory: storageDirectory)
        let session = makeSession()

        // Persist session (should create storage dir and file)
        store.persistSession(session)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: storageDirectory.path,
                isDirectory: &isDirectory
            ),
            "Storage directory should exist"
        )
        XCTAssertTrue(
            isDirectory.boolValue,
            "Storage path should be a directory"
        )

        let storageFile = storageDirectory.appendingPathComponent(
            "sessions.json"
        )
        XCTAssertTrue(
            fileManager.fileExists(atPath: storageFile.path),
            "sessions.json file should exist"
        )

        let metadata = try store.loadAllMetadata()
        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata.first?.sessionID, session.identifier)
        XCTAssertEqual(
            metadata.first?.configuration["request"],
            .string("launch")
        )
    }

    // MARK: - Helpers

    private func makeSession() -> DAPSession {
        let manifest = DAPAdapterManifest(
            identifier: "com.valkarystudio.test",
            displayName: "Test Adapter",
            version: "1.0.0",
            runtime: .externalProcess,
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: nil,
            environment: [:],
            languages: ["test"],
            capabilities: [],
            configurationFields: [],
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: true
        )

        let configuration: [String: DAPJSONValue] = [
            "request": .string("launch"),
            "program": .string("/tmp/program"),
        ]
        let broker = DAPMessageBroker(transport: NullTransport())
        return DAPSession(
            manifest: manifest,
            configuration: configuration,
            broker: broker
        )
    }
}

private final class NullTransport: DAPTransport {
    func startReceiving(
        _ handler: @escaping @Sendable (Result<DAPMessage, DAPError>) -> Void
    ) {}
    func send(_ message: DAPMessage) throws {}
    func close() {}
}
