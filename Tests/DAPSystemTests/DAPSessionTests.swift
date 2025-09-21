//
//  DAPSessionTests.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation
import XCTest

@testable import DAPSystem

final class DAPSessionTests: XCTestCase {
    func testStartPerformsHandshakeAndLaunchesByDefault() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )
    }

    func testStartUsesAttachWhenRequested() async throws {
        let configuration: [String: DAPJSONValue] = [
            "request": .string("attach"),
            "processId": .number(42),
        ]

        let (session, transport) = makeSession(configuration: configuration)

        let expectedArguments: [String: DAPJSONValue] = [
            "processId": .number(42)
        ]

        try await startSession(
            session,
            transport: transport,
            expectedCommand: "attach",
            expectedArguments: expectedArguments
        )
    }

    func testUpdatingConditionalBreakpointsSynchronizesWithAdapter()
        async throws
    {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(
            configuration: configuration,
            supportsConditionalBreakpoints: true
        )

        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let fileOne = URL(fileURLWithPath: "/tmp/file1.swift")
        let fileTwo = URL(fileURLWithPath: "/tmp/file2.swift")
        let breakpoints = [
            DAPConditionalBreakpoint(
                fileURL: fileOne,
                line: 4,
                condition: "x > 1",
                hitCondition: "5",
                logMessage: "hit"
            ),
            DAPConditionalBreakpoint(
                fileURL: fileTwo,
                line: 10,
                condition: "y == 3"
            ),
        ]

        session.updateConditionalBreakpoints(breakpoints)

        var updatedPaths: [String] = []

        try await waitForRequests(on: transport, count: 1)
        guard case .request(let firstRequest) = transport.sentMessages[0] else {
            return XCTFail("Expected first setBreakpoints request to be sent")
        }
        XCTAssertEqual(firstRequest.command, "setBreakpoints")
        if let path = firstRequest.arguments?.objectValue?["source"]?
            .objectValue?["path"]?.stringValue
        {
            updatedPaths.append(path)
        }
        transport.sendResponse(
            to: firstRequest,
            body: .object(["breakpoints": .array([])])
        )

        try await waitForRequests(on: transport, count: 2)
        guard case .request(let secondRequest) = transport.sentMessages[1]
        else {
            return XCTFail("Expected second setBreakpoints request")
        }
        XCTAssertEqual(secondRequest.command, "setBreakpoints")
        if let path = secondRequest.arguments?.objectValue?["source"]?
            .objectValue?["path"]?.stringValue
        {
            updatedPaths.append(path)
        }
        transport.sendResponse(
            to: secondRequest,
            body: .object(["breakpoints": .array([])])
        )

        XCTAssertEqual(Set(updatedPaths), Set([fileOne.path, fileTwo.path]))
    }

    func testExecutionControlCommandsSendExpectedRequests() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration,
            capabilities: [
                "supportsStepBack": .bool(true),
                "supportsStepInTargetsRequest": .bool(true),
            ]
        )

        transport.clearSentMessages()

        let continueTask = Task {
            try await session.continueExecution(threadID: 7)
        }
        try await waitForRequests(on: transport, count: 1)
        guard case .request(let continueRequest) = transport.sentMessages[0]
        else {
            return XCTFail("Expected continue request")
        }
        XCTAssertEqual(continueRequest.command, "continue")
        XCTAssertEqual(
            continueRequest.arguments?.objectValue?["threadId"]?.intValue,
            7
        )
        transport.sendResponse(
            to: continueRequest,
            body: .object(["allThreadsContinued": .bool(true)])
        )
        let continueResult = try await continueTask.value
        XCTAssertTrue(continueResult)

        let pauseTask = Task { try await session.pause(threadID: 7) }
        try await waitForRequests(on: transport, count: 2)
        guard case .request(let pauseRequest) = transport.sentMessages[1] else {
            return XCTFail("Expected pause request")
        }
        XCTAssertEqual(pauseRequest.command, "pause")
        XCTAssertEqual(
            pauseRequest.arguments?.objectValue?["threadId"]?.intValue,
            7
        )
        transport.sendResponse(to: pauseRequest, body: nil)
        _ = try await pauseTask.value

        let stepInTask = Task {
            try await session.stepIn(
                threadID: 7,
                targetID: 3,
                options: DAPSteppingOptions(
                    singleThread: true,
                    granularity: .instruction
                )
            )
        }
        try await waitForRequests(on: transport, count: 3)
        guard case .request(let stepInRequest) = transport.sentMessages[2]
        else {
            return XCTFail("Expected stepIn request")
        }
        XCTAssertEqual(stepInRequest.command, "stepIn")
        let stepInArguments = stepInRequest.arguments?.objectValue
        XCTAssertEqual(stepInArguments?["threadId"]?.intValue, 7)
        XCTAssertEqual(stepInArguments?["targetId"]?.intValue, 3)
        XCTAssertEqual(stepInArguments?["singleThread"]?.boolValue, true)
        XCTAssertEqual(
            stepInArguments?["granularity"]?.stringValue,
            "instruction"
        )
        transport.sendResponse(to: stepInRequest, body: nil)
        _ = try await stepInTask.value

        let stepOutTask = Task {
            try await session.stepOut(
                threadID: 7,
                options: DAPSteppingOptions(granularity: .line)
            )
        }
        try await waitForRequests(on: transport, count: 4)
        guard case .request(let stepOutRequest) = transport.sentMessages[3]
        else {
            return XCTFail("Expected stepOut request")
        }
        XCTAssertEqual(stepOutRequest.command, "stepOut")
        XCTAssertEqual(
            stepOutRequest.arguments?.objectValue?["granularity"]?.stringValue,
            "line"
        )
        transport.sendResponse(to: stepOutRequest, body: nil)
        _ = try await stepOutTask.value

        let stepOverTask = Task {
            try await session.stepOver(
                threadID: 7,
                options: DAPSteppingOptions(singleThread: true)
            )
        }
        try await waitForRequests(on: transport, count: 5)
        guard case .request(let stepOverRequest) = transport.sentMessages[4]
        else {
            return XCTFail("Expected step over request")
        }
        XCTAssertEqual(stepOverRequest.command, "next")
        XCTAssertEqual(
            stepOverRequest.arguments?.objectValue?["singleThread"]?.boolValue,
            true
        )
        transport.sendResponse(to: stepOverRequest, body: nil)
        _ = try await stepOverTask.value

        let stepBackTask = Task {
            try await session.stepBack(
                threadID: 7,
                options: DAPSteppingOptions(granularity: .statement)
            )
        }
        try await waitForRequests(on: transport, count: 6)
        guard case .request(let stepBackRequest) = transport.sentMessages[5]
        else {
            return XCTFail("Expected stepBack request")
        }
        XCTAssertEqual(stepBackRequest.command, "stepBack")
        XCTAssertEqual(
            stepBackRequest.arguments?
                .objectValue?["granularity"]?.stringValue,
            "statement"
        )
        transport.sendResponse(to: stepBackRequest, body: nil)
        _ = try await stepBackTask.value
    }

    func testFetchingRuntimeStateParsesResponses() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let threadsTask = Task { try await session.fetchThreads() }
        try await waitForRequests(on: transport, count: 1)
        guard case .request(let threadsRequest) = transport.sentMessages[0]
        else {
            return XCTFail("Expected threads request")
        }
        XCTAssertEqual(threadsRequest.command, "threads")
        transport.sendResponse(
            to: threadsRequest,
            body: .object([
                "threads": .array([
                    .object(["id": .number(1), "name": .string("main")])
                ])
            ])
        )
        let threadList = try await threadsTask.value
        XCTAssertEqual(threadList, [DAPThread(id: 1, name: "main")])

        let stackTask = Task { try await session.fetchStackTrace(threadID: 1) }
        try await waitForRequests(on: transport, count: 2)
        guard case .request(let stackRequest) = transport.sentMessages[1] else {
            return XCTFail("Expected stackTrace request")
        }
        XCTAssertEqual(stackRequest.command, "stackTrace")
        transport.sendResponse(
            to: stackRequest,
            body: .object([
                "stackFrames": .array([
                    .object([
                        "id": .number(10),
                        "name": .string("func"),
                        "line": .number(12),
                        "column": .number(3),
                        "source": .object([
                            "name": .string("file.swift"),
                            "path": .string("/tmp/file.swift"),
                        ]),
                    ])
                ])
            ])
        )
        let frames = try await stackTask.value
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(
            frames.first?.source?.path,
            URL(fileURLWithPath: "/tmp/file.swift")
        )

        let scopesTask = Task { try await session.fetchScopes(frameID: 10) }
        try await waitForRequests(on: transport, count: 3)
        guard case .request(let scopesRequest) = transport.sentMessages[2]
        else {
            return XCTFail("Expected scopes request")
        }
        XCTAssertEqual(scopesRequest.command, "scopes")
        transport.sendResponse(
            to: scopesRequest,
            body: .object([
                "scopes": .array([
                    .object([
                        "name": .string("Locals"),
                        "variablesReference": .number(99),
                        "expensive": .bool(false),
                    ])
                ])
            ])
        )
        let scopeValues = try await scopesTask.value
        XCTAssertEqual(scopeValues.count, 1)

        let variablesTask = Task {
            try await session.fetchVariables(reference: 99)
        }
        try await waitForRequests(on: transport, count: 4)
        guard case .request(let variablesRequest) = transport.sentMessages[3]
        else {
            return XCTFail("Expected variables request")
        }
        XCTAssertEqual(variablesRequest.command, "variables")
        transport.sendResponse(
            to: variablesRequest,
            body: .object([
                "variables": .array([
                    .object([
                        "name": .string("value"),
                        "value": .string("42"),
                        "variablesReference": .number(0),
                    ])
                ])
            ])
        )
        let variableValues = try await variablesTask.value
        XCTAssertEqual(variableValues.first?.value, "42")
    }

    func testFetchStepInTargetsParsesTargets() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration,
            capabilities: ["supportsStepInTargetsRequest": .bool(true)]
        )

        transport.clearSentMessages()

        let targetsTask = Task {
            try await session.fetchStepInTargets(frameID: 42)
        }
        try await waitForRequests(on: transport, count: 1)
        guard case .request(let targetsRequest) = transport.sentMessages[0]
        else {
            return XCTFail("Expected stepInTargets request")
        }
        XCTAssertEqual(targetsRequest.command, "stepInTargets")
        XCTAssertEqual(
            targetsRequest.arguments?.objectValue?["frameId"]?.intValue,
            42
        )

        let responseTargets: [DAPJSONValue] = [
            .object([
                "id": .number(1),
                "label": .string("entry"),
                "line": .number(10),
                "column": .number(2),
            ]),
            .object([
                "id": .number(2),
                "label": .string("alternate"),
                "instructionPointerReference": .string("0xFFEE"),
            ]),
        ]

        transport.sendResponse(
            to: targetsRequest,
            body: .object(["targets": .array(responseTargets)])
        )

        let targets = try await targetsTask.value
        XCTAssertEqual(
            targets,
            [
                DAPStepInTarget(
                    id: 1,
                    label: "entry",
                    line: 10,
                    column: 2
                ),
                DAPStepInTarget(
                    id: 2,
                    label: "alternate",
                    instructionPointerReference: "0xFFEE"
                ),
            ]
        )
    }

    func testStepBackThrowsWhenCapabilityMissing() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        do {
            try await session.stepBack(threadID: 9)
            XCTFail("Expected stepBack to throw without capability")
        } catch let error as DAPError {
            guard case .unsupportedFeature(let message) = error else {
                return XCTFail("Expected unsupportedFeature error")
            }
            XCTAssertTrue(message.contains("supportsStepBack"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(transport.sentMessages.isEmpty)
    }

    func testFetchStepInTargetsRequiresCapability() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        do {
            _ = try await session.fetchStepInTargets(frameID: 7)
            XCTFail("Expected fetchStepInTargets to throw without capability")
        } catch let error as DAPError {
            guard case .unsupportedFeature(let message) = error else {
                return XCTFail("Expected unsupportedFeature error")
            }
            XCTAssertTrue(message.contains("supportsStepInTargetsRequest"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(transport.sentMessages.isEmpty)
    }

    func testRuntimeEventsEmitSessionEvents() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let recorder = EventRecorder()
        let expectation = expectation(description: "Received events")
        expectation.expectedFulfillmentCount = 4

        session.onEvent = { event in
            Task {
                await recorder.append(event)
                expectation.fulfill()
            }
        }

        transport.sendEvent(
            name: "stopped",
            body: .object(["reason": .string("break"), "threadId": .number(7)])
        )
        transport.sendEvent(
            name: "continued",
            body: .object(["threadId": .number(7)])
        )
        transport.sendEvent(
            name: "output",
            body: .object([
                "output": .string("log"), "category": .string("stdout"),
            ])
        )
        transport.sendEvent(name: "terminated", body: .object([:]))

        await fulfillment(of: [expectation], timeout: 1.0)

        let receivedEvents = await recorder.allEvents()

        XCTAssertTrue(
            receivedEvents.contains(where: {
                if case .stopped(let payload) = $0 {
                    return payload.threadId == 7
                }
                return false
            })
        )
        XCTAssertTrue(
            receivedEvents.contains(where: {
                if case .continued(let payload) = $0 {
                    return payload.threadId == 7
                }
                return false
            })
        )
        XCTAssertTrue(
            receivedEvents.contains(where: {
                if case .output(let payload) = $0 {
                    return payload.output == "log"
                }
                return false
            })
        )
        XCTAssertTrue(
            receivedEvents.contains(where: { event in
                if case .terminated = event { return true }
                return false
            })
        )
    }

    func testExtendedProtocolRequests() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let (session, transport) = makeSession(configuration: configuration)
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let exceptionTask = Task {
            try await session.setExceptionBreakpoints(["all"])
        }
        try await waitForRequests(on: transport, count: 1)
        guard case .request(let exceptionRequest) = transport.sentMessages[0]
        else {
            return XCTFail("Expected setExceptionBreakpoints request")
        }
        XCTAssertEqual(exceptionRequest.command, "setExceptionBreakpoints")
        let filters = exceptionRequest.arguments?.objectValue?["filters"]?
            .arrayValue?.compactMap { $0.stringValue }
        XCTAssertEqual(filters, ["all"])
        transport.sendResponse(to: exceptionRequest, body: nil)
        _ = try await exceptionTask.value

        let dataBreakpoint = DAPDataBreakpoint(
            dataId: "watch",
            accessType: "write"
        )
        let dataTask = Task {
            try await session.setDataBreakpoints([dataBreakpoint])
        }
        try await waitForRequests(on: transport, count: 2)
        guard case .request(let dataRequest) = transport.sentMessages[1] else {
            return XCTFail("Expected setDataBreakpoints request")
        }
        XCTAssertEqual(dataRequest.command, "setDataBreakpoints")
        transport.sendResponse(
            to: dataRequest,
            body: .object([
                "breakpoints": .array([
                    .object(["verified": .bool(true), "id": .string("watch")])
                ])
            ])
        )
        let dataBreakpointStatuses = try await dataTask.value
        XCTAssertEqual(dataBreakpointStatuses.first?.id, "watch")

        let sourcesTask = Task { try await session.fetchLoadedSources() }
        try await waitForRequests(on: transport, count: 3)
        guard case .request(let sourcesRequest) = transport.sentMessages[2]
        else {
            return XCTFail("Expected loadedSources request")
        }
        transport.sendResponse(
            to: sourcesRequest,
            body: .object([
                "sources": .array([
                    .object([
                        "name": .string("File"),
                        "path": .string("/tmp/file.swift"),
                    ])
                ])
            ])
        )
        let loadedSources = try await sourcesTask.value
        XCTAssertEqual(
            loadedSources.first?.source.path,
            URL(fileURLWithPath: "/tmp/file.swift")
        )

        let modulesTask = Task { try await session.fetchModules() }
        try await waitForRequests(on: transport, count: 4)
        guard case .request(let modulesRequest) = transport.sentMessages[3]
        else {
            return XCTFail("Expected modules request")
        }
        transport.sendResponse(
            to: modulesRequest,
            body: .object([
                "modules": .array([
                    .object(["id": .string("mod"), "name": .string("Module")])
                ])
            ])
        )
        let moduleList = try await modulesTask.value
        XCTAssertEqual(moduleList.first?.name, "Module")

        let completionsTask = Task {
            try await session.fetchCompletions(text: "pri", column: 3, line: 1)
        }
        try await waitForRequests(on: transport, count: 5)
        guard case .request(let completionsRequest) = transport.sentMessages[4]
        else {
            return XCTFail("Expected completions request")
        }
        transport.sendResponse(
            to: completionsRequest,
            body: .object([
                "items": .array([
                    .object([
                        "label": .string("print"), "text": .string("print"),
                    ])
                ])
            ])
        )
        let completionItems = try await completionsTask.value
        XCTAssertEqual(completionItems.first?.label, "print")

        let readTask = Task {
            try await session.readMemory(memoryReference: "0x1", count: 2)
        }
        try await waitForRequests(on: transport, count: 6)
        guard case .request(let readRequest) = transport.sentMessages[5] else {
            return XCTFail("Expected readMemory request")
        }
        transport.sendResponse(
            to: readRequest,
            body: .object([
                "address": .string("0x1"),
                "data": .string(Data([0x01, 0x02]).base64EncodedString()),
            ])
        )
        let readResult = try await readTask.value
        XCTAssertEqual(readResult.data, Data([0x01, 0x02]))

        let writeTask = Task {
            try await session.writeMemory(
                memoryReference: "0x1",
                data: Data([0xFF])
            )
        }
        try await waitForRequests(on: transport, count: 7)
        guard case .request(let writeRequest) = transport.sentMessages[6] else {
            return XCTFail("Expected writeMemory request")
        }
        transport.sendResponse(
            to: writeRequest,
            body: .object(["bytesWritten": .number(1)])
        )
        let writeResult = try await writeTask.value
        XCTAssertEqual(writeResult.bytesWritten, 1)
    }

    func testRunInTerminalRequestsAreDelegatedToHost() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let delegate = HostDelegateStub()
        await delegate.setRunInTerminalResult(
            DAPRunInTerminalResult(processId: 1234, shellProcessId: 5678)
        )

        let (session, transport) = makeSession(
            configuration: configuration,
            hostDelegate: delegate
        )
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let requestArguments: DAPJSONValue = .object([
            "args": .array([.string("echo"), .string("Hello")]),
            "cwd": .string("/tmp"),
            "kind": .string("integrated"),
            "env": .object(["FOO": .string("BAR")]),
        ])

        transport.sendHostRequest(
            command: "runInTerminal",
            arguments: requestArguments
        )

        try await waitForRequests(on: transport, count: 1)
        guard case .response(let response) = transport.sentMessages[0] else {
            return XCTFail("Expected runInTerminal response")
        }
        XCTAssertTrue(response.success)
        XCTAssertEqual(
            response.body?.objectValue?["processId"]?.intValue,
            1234
        )
        XCTAssertEqual(
            response.body?.objectValue?["shellProcessId"]?.intValue,
            5678
        )

        let recordedRequests = await delegate.recordedRunInTerminalRequests()
        XCTAssertEqual(recordedRequests.count, 1)
        XCTAssertEqual(recordedRequests.first?.cwd, "/tmp")
        XCTAssertEqual(recordedRequests.first?.args, ["echo", "Hello"])
        XCTAssertEqual(recordedRequests.first?.env?["FOO"], "BAR")
    }

    func testStartDebuggingRequestsAreDelegatedToHost() async throws {
        let configuration: [String: DAPJSONValue] = [
            "program": .string("/tmp/app")
        ]

        let delegate = HostDelegateStub()
        await delegate.setStartDebuggingResult(
            DAPStartDebuggingResult(
                body: .object(["accepted": .bool(true)])
            )
        )

        let (session, transport) = makeSession(
            configuration: configuration,
            hostDelegate: delegate
        )
        try await startSession(
            session,
            transport: transport,
            expectedCommand: "launch",
            expectedArguments: configuration
        )

        transport.clearSentMessages()

        let startArguments: DAPJSONValue = .object([
            "request": .string("launch"),
            "configuration": .object([
                "name": .string("child"),
                "program": .string("/tmp/child"),
            ]),
        ])

        transport.sendHostRequest(
            command: "startDebugging",
            arguments: startArguments
        )

        try await waitForRequests(on: transport, count: 1)
        guard case .response(let response) = transport.sentMessages[0] else {
            return XCTFail("Expected startDebugging response")
        }
        XCTAssertTrue(response.success)
        XCTAssertEqual(
            response.body?.objectValue?["accepted"]?.boolValue,
            true
        )

        let recordedRequests = await delegate.recordedStartDebuggingRequests()
        XCTAssertEqual(recordedRequests.count, 1)
        XCTAssertEqual(recordedRequests.first?.request, "launch")
        XCTAssertEqual(
            recordedRequests.first?.configuration["program"]?.stringValue,
            "/tmp/child"
        )
    }

    // MARK: - Helpers

    private func makeSession(
        configuration: [String: DAPJSONValue],
        supportsConditionalBreakpoints: Bool = true,
        supportsWatchExpressions: Bool = true,
        hostDelegate: DAPSessionHostDelegate? = nil
    ) -> (DAPSession, FakeTransport) {
        let transport = FakeTransport()
        let broker = DAPMessageBroker(transport: transport)

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
            supportsConditionalBreakpoints: supportsConditionalBreakpoints,
            supportsWatchExpressions: supportsWatchExpressions,
            supportsPersistence: false
        )

        let session = DAPSession(
            manifest: manifest,
            configuration: configuration,
            broker: broker,
            hostDelegate: hostDelegate
        )

        return (session, transport)
    }

    private func startSession(
        _ session: DAPSession,
        transport: FakeTransport,
        expectedCommand: String,
        expectedArguments: [String: DAPJSONValue],
        capabilities: [String: DAPJSONValue] = [:],
        timeout: TimeInterval = 1.0
    ) async throws {
        let startTask = Task { try await session.start() }

        try await waitForRequests(on: transport, count: 1, timeout: timeout)
        guard case .request(let initializeRequest) = transport.sentMessages[0]
        else {
            return XCTFail("Expected initialize request to be sent first")
        }
        XCTAssertEqual(initializeRequest.command, "initialize")
        transport.sendResponse(
            to: initializeRequest,
            body: .object(["capabilities": .object(capabilities)])
        )

        transport.sendInitializedEvent()

        try await waitForRequests(on: transport, count: 2, timeout: timeout)
        guard case .request(let configurationDone) = transport.sentMessages[1]
        else {
            return XCTFail("Expected configurationDone request")
        }
        transport.sendResponse(to: configurationDone, body: nil)

        try await waitForRequests(on: transport, count: 3, timeout: timeout)
        guard case .request(let request) = transport.sentMessages[2] else {
            return XCTFail("Expected \(expectedCommand) request")
        }
        XCTAssertEqual(request.command, expectedCommand)
        XCTAssertEqual(request.arguments?.objectValue, expectedArguments)
        transport.sendResponse(to: request, body: nil)

        try await waitForRequests(on: transport, count: 4, timeout: timeout)
        guard case .request(let exceptionRequest) = transport.sentMessages[3]
        else {
            return XCTFail("Expected setExceptionBreakpoints request")
        }
        XCTAssertEqual(exceptionRequest.command, "setExceptionBreakpoints")
        transport.sendResponse(to: exceptionRequest, body: nil)

        _ = try await startTask.value
    }

    private func waitForRequests(
        on transport: FakeTransport,
        count: Int,
        timeout: TimeInterval = 1.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if transport.sentMessages.count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for \(count) messages to be sent")
    }
}

private actor HostDelegateStub: DAPSessionHostDelegate {
    private var runInTerminalResult = DAPRunInTerminalResult()
    private var startDebuggingResult = DAPStartDebuggingResult()
    private var runInTerminalRequests: [DAPRunInTerminalRequest] = []
    private var startDebuggingRequests: [DAPStartDebuggingRequest] = []

    func setRunInTerminalResult(_ result: DAPRunInTerminalResult) {
        runInTerminalResult = result
    }

    func setStartDebuggingResult(_ result: DAPStartDebuggingResult) {
        startDebuggingResult = result
    }

    func recordedRunInTerminalRequests() -> [DAPRunInTerminalRequest] {
        runInTerminalRequests
    }

    func recordedStartDebuggingRequests() -> [DAPStartDebuggingRequest] {
        startDebuggingRequests
    }

    func session(
        _ session: DAPSession,
        runInTerminal request: DAPRunInTerminalRequest
    ) async throws -> DAPRunInTerminalResult {
        runInTerminalRequests.append(request)
        return runInTerminalResult
    }

    func session(
        _ session: DAPSession,
        startDebugging request: DAPStartDebuggingRequest
    ) async throws -> DAPStartDebuggingResult {
        startDebuggingRequests.append(request)
        return startDebuggingResult
    }
}

private final class FakeTransport: DAPTransport, @unchecked Sendable {
    private(set) var sentMessages: [DAPMessage] = []
    private var receiveHandler: ((Result<DAPMessage, DAPError>) -> Void)?
    private var nextEventSequence: Int = 1_000
    private var nextRequestSequence: Int = 2_000

    func startReceiving(
        _ handler: @escaping @Sendable (Result<DAPMessage, DAPError>) -> Void
    ) {
        receiveHandler = handler
    }

    func send(_ message: DAPMessage) throws {
        sentMessages.append(message)
    }

    func close() {}

    func sendResponse(to request: DAPRequest, body: DAPJSONValue?) {
        let response = DAPResponse(
            seq: request.seq + 100,
            requestSeq: request.seq,
            success: true,
            command: request.command,
            message: nil,
            body: body
        )
        receiveHandler?(.success(.response(response)))
    }

    func sendInitializedEvent() {
        sendEvent(name: "initialized", body: nil)
    }

    func sendEvent(name: String, body: DAPJSONValue?) {
        let event = DAPEvent(seq: nextEventSequence, event: name, body: body)
        nextEventSequence += 1
        receiveHandler?(.success(.event(event)))
    }

    func sendHostRequest(command: String, arguments: DAPJSONValue?) {
        guard let receiveHandler else { return }
        let request = DAPRequest(
            seq: nextRequestSequence,
            command: command,
            arguments: arguments
        )
        nextRequestSequence += 1
        receiveHandler(.success(.request(request)))
    }

    func clearSentMessages() {
        sentMessages.removeAll()
    }
}

private actor EventRecorder {
    private var storage: [DAPSessionEvent] = []

    func append(_ event: DAPSessionEvent) {
        storage.append(event)
    }

    func allEvents() -> [DAPSessionEvent] {
        storage
    }
}
