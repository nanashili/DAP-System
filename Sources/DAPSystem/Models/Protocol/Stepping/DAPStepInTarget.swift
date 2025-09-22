//
//  DAPStepInTarget.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPStepInTarget: Sendable, Equatable {
    public let id: Int
    public let label: String
    public let line: Int?
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?
    public let instructionPointerReference: String?

    @inlinable
    public init(
        id: Int,
        label: String,
        line: Int? = nil,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil,
        instructionPointerReference: String? = nil
    ) {
        self.id = id
        self.label = label
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
        self.instructionPointerReference = instructionPointerReference
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let id = o[_J.id]?.intValue,
            let label = o[_J.label]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "StepInTarget payload missing required fields"
            )
        }

        self.init(
            id: id,
            label: label,
            line: o[_J.line]?.intValue,
            column: o[_J.column]?.intValue,
            endLine: o[_J.endLine]?.intValue,
            endColumn: o[_J.endColumn]?.intValue,
            instructionPointerReference: o[_J.instructionPointerRef]?
                .stringValue
        )
    }
}
