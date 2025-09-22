//
//  DAPSteppingGranularity.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

public enum DAPSteppingGranularity: String, Sendable, CaseIterable {
    case statement, line, instruction
}

@frozen
public struct DAPSteppingOptions: Sendable, Equatable {
    /// If true, only the specified thread is resumed/stepped.
    public var singleThread: Bool?
    /// Step resolution granularity.
    public var granularity: DAPSteppingGranularity?

    @inlinable
    public init(
        singleThread: Bool? = nil,
        granularity: DAPSteppingGranularity? = nil
    ) {
        self.singleThread = singleThread
        self.granularity = granularity
    }
}

extension DAPSteppingOptions {
    /// Request arguments encoder (minimal allocations).
    @inlinable
    public func asDAPArguments() -> [String: DAPJSONValue] {
        var a: [String: DAPJSONValue] = .init(minimumCapacity: 2)
        _putIfSomeBool(&a, key: "singleThread", value: singleThread)
        if let g = granularity { a["granularity"] = .string(g.rawValue) }
        return a
    }
}
