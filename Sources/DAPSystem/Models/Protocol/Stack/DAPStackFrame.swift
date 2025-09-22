//
//  DAPStackFrame.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPStackFrame: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let source: DAPSource?
    public let line: Int
    public let column: Int
    public let endLine: Int?
    public let endColumn: Int?

    @inlinable
    public init(
        id: Int,
        name: String,
        source: DAPSource?,
        line: Int,
        column: Int,
        endLine: Int?,
        endColumn: Int?
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let id = o[_J.id]?.intValue,
            let name = o[_J.name]?.stringValue,
            let line = o[_J.line]?.intValue,
            let column = o[_J.column]?.intValue
        else {
            throw DAPError.invalidResponse(
                "StackFrame payload missing required fields"
            )
        }

        let src: DAPSource? = {
            if let sv = o[_J.source] { return try? DAPSource(json: sv) }
            return nil
        }()

        self.init(
            id: id,
            name: name,
            source: src,
            line: line,
            column: column,
            endLine: o[_J.endLine]?.intValue,
            endColumn: o[_J.endColumn]?.intValue
        )
    }
}
