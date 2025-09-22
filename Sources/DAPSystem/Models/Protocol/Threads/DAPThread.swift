//
//  DAPThread.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPThread: Sendable, Equatable {
    public let id: Int
    public let name: String

    @inlinable
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let id = o[_J.id]?.intValue,
            let name = o[_J.name]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "Thread payload missing required fields"
            )
        }
        self.init(id: id, name: name)
    }
}
