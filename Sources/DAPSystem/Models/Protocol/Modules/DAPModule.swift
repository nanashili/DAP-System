//
//  DAPModule.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPModule: Sendable, Equatable {
    /// Adapter-specified module identifier (string or number in the wire protocol).
    public let id: String
    public let name: String
    public let path: URL?
    public let symbolFilePath: URL?
    public let isOptimized: Bool?

    @inlinable
    public init(
        id: String,
        name: String,
        path: URL?,
        symbolFilePath: URL?,
        isOptimized: Bool?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.symbolFilePath = symbolFilePath
        self.isOptimized = isOptimized
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let idValue = o[_J.id],
            let name = o[_J.name]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "Module payload missing required fields"
            )
        }

        let idString: String = {
            if let s = idValue.stringValue { return s }
            if let n = idValue.intValue { return String(n) }
            return ""
        }()
        guard !idString.isEmpty else {
            throw DAPError.invalidResponse(
                "Module identifier must be a string or number"
            )
        }

        let pathURL: URL? = {
            if let s = o[_J.path]?.stringValue {
                return URL(fileURLWithPath: s)
            }
            return nil
        }()
        let symURL: URL? = {
            if let s = o["symbolFilePath"]?.stringValue {
                return URL(fileURLWithPath: s)
            }
            return nil
        }()

        self.init(
            id: idString,
            name: name,
            path: pathURL,
            symbolFilePath: symURL,
            isOptimized: o["isOptimized"]?.boolValue
        )
    }
}
