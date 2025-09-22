//
//  DAPVariable.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPVariable: Sendable, Equatable {
    public let name: String
    public let value: String
    public let type: String?
    public let variablesReference: Int
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let evaluateName: String?

    @inlinable
    public init(
        name: String,
        value: String,
        type: String?,
        variablesReference: Int,
        namedVariables: Int?,
        indexedVariables: Int?,
        evaluateName: String?
    ) {
        self.name = name
        self.value = value
        self.type = type
        self.variablesReference = variablesReference
        self.namedVariables = namedVariables
        self.indexedVariables = indexedVariables
        self.evaluateName = evaluateName
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let name = o[_J.name]?.stringValue,
            let value = o[_J.value]?.stringValue,
            let vr = o[_J.variablesReference]?.intValue
        else {
            throw DAPError.invalidResponse(
                "Variable payload missing required fields"
            )
        }

        self.init(
            name: name,
            value: value,
            type: o[_J.type]?.stringValue,
            variablesReference: vr,
            namedVariables: o[_J.namedVariables]?.intValue,
            indexedVariables: o[_J.indexedVariables]?.intValue,
            evaluateName: o[_J.evaluateName]?.stringValue
        )
    }
}
