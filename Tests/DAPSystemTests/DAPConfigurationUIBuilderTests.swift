//
//  DAPConfigurationUIBuilderTests.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import XCTest

@testable import DAPSystem

final class DAPConfigurationUIBuilderTests: XCTestCase {
    func testBuildsSectionsWithFieldMetadata() {
        // -- Arrange fields & manifest
        let fields: [DAPAdapterConfigurationField] = [
            .init(
                key: "program",
                title: "Program",
                type: .text,
                defaultValue: nil,
                description: "Path to the executable"
            ),
            .init(
                key: "port",
                title: "Port",
                type: .number,
                defaultValue: nil,
                description: "Debugger port"
            ),
            .init(
                key: "token",
                title: "Token",
                type: .password,
                defaultValue: .string("secret"),
                description: "Authentication token"
            ),
            .init(
                key: "trace",
                title: "Trace",
                type: .toggle,
                defaultValue: .bool(false),
                description: "Enable trace logging"
            ),
            .init(
                key: "runtime",
                title: "Runtime",
                type: .selection,
                defaultValue: .string("node"),
                description: "Runtime selection",
                options: ["node", "deno"]
            ),
        ]
        let manifest = DAPAdapterManifest(
            identifier: "test.ui.builder",
            displayName: "Test Adapter",
            version: "1.0.0",
            runtime: .externalProcess,
            executable: "/usr/bin/env",
            arguments: ["bash"],
            workingDirectory: nil,
            environment: [:],
            languages: ["swift"],
            capabilities: [],
            configurationFields: fields,
            supportsConditionalBreakpoints: false,
            supportsWatchExpressions: false,
            supportsPersistence: false
        )

        let builder = DAPConfigurationUIBuilder()

        // -- Act
        let sections = builder.makeSections(for: manifest)

        // -- Assert: Sections
        XCTContext.runActivity(named: "Validate Sections") { _ in
            XCTAssertEqual(
                sections.count,
                2,
                "Should produce required and optional sections"
            )
            XCTAssertEqual(sections[0].title, "Test Adapter (Required)")
            XCTAssertEqual(sections[1].title, "Test Adapter (Optional)")
        }

        // -- Assert: Required fields
        let requiredFields = sections[0].fields
        XCTContext.runActivity(named: "Validate Required Fields") { _ in
            XCTAssertEqual(requiredFields.map(\.key), ["program", "port"])
            XCTAssertEqual(requiredFields.map(\.isRequired), [true, true])
            XCTAssertEqual(requiredFields.map(\.controlType), [.text, .number])
        }

        // -- Assert: Optional fields
        let optionalFields = sections[1].fields
        XCTContext.runActivity(named: "Validate Optional Fields") { _ in
            XCTAssertEqual(
                optionalFields.map(\.key),
                ["token", "trace", "runtime"]
            )
            XCTAssertEqual(
                optionalFields.map(\.isRequired),
                [false, false, false]
            )

            XCTAssertEqual(optionalFields[0].controlType, .secureText)
            XCTAssertEqual(optionalFields[0].defaultValue, .string("secret"))
            XCTAssertEqual(
                optionalFields[0].description,
                "Authentication token"
            )

            XCTAssertEqual(optionalFields[1].controlType, .toggle)
            XCTAssertEqual(optionalFields[1].defaultValue, .bool(false))

            XCTAssertEqual(
                optionalFields[2].controlType,
                .picker(options: ["node", "deno"])
            )
            XCTAssertEqual(optionalFields[2].defaultValue, .string("node"))
            XCTAssertEqual(optionalFields[2].description, "Runtime selection")
        }
    }
}
