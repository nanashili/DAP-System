//
//  DAPScope.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPScope: Sendable, Equatable {
    public let name: String
    public let variablesReference: Int
    public let expensive: Bool
    public let presentationHint: String?
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let source: DAPSource?
    public let line: Int?
    public let column: Int?

    @inlinable
    public init(
        name: String,
        variablesReference: Int,
        expensive: Bool,
        presentationHint: String?,
        namedVariables: Int?,
        indexedVariables: Int?,
        source: DAPSource?,
        line: Int?,
        column: Int?
    ) {
        self.name = name
        self.variablesReference = variablesReference
        self.expensive = expensive
        self.presentationHint = presentationHint
        self.namedVariables = namedVariables
        self.indexedVariables = indexedVariables
        self.source = source
        self.line = line
        self.column = column
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let name = o[_J.name]?.stringValue,
            let vr = o[_J.variablesReference]?.intValue,
            let expensive = o[_J.expensive]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Scope payload missing required fields"
            )
        }

        let src: DAPSource? = {
            if let sv = o[_J.source] { return try? DAPSource(json: sv) }
            return nil
        }()

        self.init(
            name: name,
            variablesReference: vr,
            expensive: expensive,
            presentationHint: o[_J.presentationHint]?.stringValue,
            namedVariables: o[_J.namedVariables]?.intValue,
            indexedVariables: o[_J.indexedVariables]?.intValue,
            source: src,
            line: o[_J.line]?.intValue,
            column: o[_J.column]?.intValue
        )
    }
}
