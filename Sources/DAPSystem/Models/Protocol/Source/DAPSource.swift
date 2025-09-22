//
//  DAPSource+Model.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPSource: Sendable, Equatable {
    /// Display name of the source (e.g., filename). Optional.
    public let name: String?
    /// Local filesystem path for the source, if any. Optional.
    public let path: URL?
    /// Reference into the adapter's virtual source store (non-file sources).
    public let sourceReference: Int?

    @inlinable
    public init(name: String?, path: URL?, sourceReference: Int?) {
        self.name = name
        self.path = path
        self.sourceReference = sourceReference
    }

    /// Tight, fail-fast parser; avoids Codable overhead.
    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json else {
            throw DAPError.invalidResponse("Source payload must be an object")
        }
        let pathURL: URL? = {
            if let s = o[_J.path]?.stringValue {
                return URL(fileURLWithPath: s)
            }
            return nil
        }()
        self.init(
            name: o[_J.name]?.stringValue,
            path: pathURL,
            sourceReference: o[_J.sourceReference]?.intValue
        )
    }
}

@frozen
public struct DAPLoadedSource: Sendable, Equatable {
    public let source: DAPSource

    @inlinable
    public init(source: DAPSource) {
        self.source = source
    }

    init(json: DAPJSONValue) throws {
        self.init(source: try DAPSource(json: json))
    }
}

extension DAPSource {
    /// JSON for requests (e.g., stackTrace > Source).
    public func asDAPRequestValue() -> DAPJSONValue {
        var obj: [String: DAPJSONValue] = .init(minimumCapacity: 3)
        _putIfNonEmpty(&obj, key: _J.name, string: name)
        if let path { obj[_J.path] = .string(path.path) }
        _putIfSomeInt(&obj, key: _J.sourceReference, value: sourceReference)
        return .object(obj)
    }
}
