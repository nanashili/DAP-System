//
//  PipeDAPTransport.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  Implements DAPTransport using a local child process and stdio pipes.
//  - Reads/writes using Content-Length framed JSON (VS Code DAP standard).
//  - Handles partial messages, async drains, and automatic cleanup.
//

import Foundation

final class PipeDAPTransport: NSObject, DAPTransport {
    private let process: Process
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let queue = DispatchQueue(
        label: "com.valkarystudio.debugger.transport"
    )
    private var buffer = Data()
    private let headerTerminator = "\r\n\r\n".data(using: .utf8)!
    private var handler: ((Result<DAPMessage, DAPError>) -> Void)?
    private var isClosed = false

    init(process: Process) {
        self.process = process
        super.init()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
    }

    func startReceiving(
        _ handler: @escaping @Sendable (Result<DAPMessage, DAPError>) -> Void
    ) {
        self.handler = handler
        outputPipe.fileHandleForReading.readabilityHandler = {
            [weak self] handle in
            guard let self, !self.isClosed else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.queue.async {
                self.buffer.append(data)
                self.drainBuffer()
            }
        }
    }

    func send(_ message: DAPMessage) throws {
        let payload = try encoder.encode(message)
        guard
            let header = "Content-Length: \(payload.count)\r\n\r\n".data(
                using: .utf8
            )
        else {
            throw DAPError.transportFailure(
                "Unable to encode Content-Length header"
            )
        }
        inputPipe.fileHandleForWriting.write(header)
        inputPipe.fileHandleForWriting.write(payload)
    }

    func close() {
        isClosed = true
        outputPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForReading.close()
        process.terminate()
    }

    /// Reads and parses messages from the buffer, handling partial reads and out-of-sync state.
    private func drainBuffer() {
        while true {
            guard let headerRange = buffer.range(of: headerTerminator) else {
                // Wait for more header data
                return
            }
            let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
            guard let headerString = String(data: headerData, encoding: .utf8)
            else {
                handler?(
                    .failure(.invalidMessage("Unable to decode DAP header"))
                )
                buffer.removeAll()
                return
            }
            // Parse Content-Length header
            let lines = headerString.components(separatedBy: "\r\n")
            guard
                let contentLengthLine = lines.first(where: {
                    $0.lowercased().hasPrefix("content-length")
                }),
                let contentLength = Int(
                    contentLengthLine.split(separator: ":").last?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                )
            else {
                handler?(
                    .failure(
                        .invalidMessage(
                            "Malformed or missing Content-Length header"
                        )
                    )
                )
                buffer.removeAll()
                return
            }
            let messageStart = headerRange.upperBound
            guard buffer.count >= messageStart + contentLength else {
                // Wait for full message payload
                return
            }
            let messageData = buffer.subdata(
                in: messageStart..<(messageStart + contentLength)
            )
            buffer.removeSubrange(0..<(messageStart + contentLength))

            do {
                let message = try decoder.decode(
                    DAPMessage.self,
                    from: messageData
                )
                handler?(.success(message))
            } catch {
                handler?(
                    .failure(
                        .invalidMessage(
                            "Failed to decode DAP message: \(error.localizedDescription)"
                        )
                    )
                )
            }
        }
    }
}

// MARK: - Adapter: ExternalProcessDAPAdapter

open class ExternalProcessDAPAdapter: BaseDAPAdapter, @unchecked Sendable {
    private var process: Process?
    private var broker: DAPMessageBroker?

    public override func prepareSession(configuration: [String: DAPJSONValue])
        throws -> DAPSession
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: manifest.executable)
        process.arguments = manifest.arguments
        if let workingDirectory = manifest.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = resolvedEnvironment()

        let transport = PipeDAPTransport(process: process)
        let broker = DAPMessageBroker(transport: transport)
        let session = DAPSession(
            manifest: manifest,
            configuration: configuration,
            broker: broker
        )

        self.process = process
        self.broker = broker
        self.session = session
        return session
    }

    public override func startSession() async throws {
        guard let process else {
            throw DAPError.processLaunchFailed(
                "Process was not prepared before startSession was called."
            )
        }
        do {
            try process.run()
        } catch {
            throw DAPError.processLaunchFailed(error.localizedDescription)
        }
        try await super.startSession()
    }

    public override func stopSession() async {
        defer { broker = nil }
        await super.stopSession()
        process?.terminate()
        process = nil
    }

    /// Merges host environment and manifest environment keys.
    open func resolvedEnvironment(hostEnvironment: [String: String]? = nil)
        -> [String: String]
    {
        var environment = hostEnvironment ?? ProcessInfo.processInfo.environment
        for (key, value) in manifest.environment {
            environment[key] = value
        }
        return environment
    }
}
