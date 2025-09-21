//
//  DAPJSON.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//


import Foundation

/// Represents arbitrary JSON data in a type-safe manner that is still compatible with
/// dynamic payloads coming from debug adapters.
public enum DAPJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DAPJSONValue])
    case object([String: DAPJSONValue])
}

extension DAPJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([DAPJSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: DAPJSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }
}

extension DAPJSONValue {
    /// Retrieves a string value if available.
    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// Retrieves a bool value if available.
    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Retrieves a dictionary value if available.
    public var objectValue: [String: DAPJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Retrieves an array value if available.
    public var arrayValue: [DAPJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// Retrieves an integer value if available.
    public var intValue: Int? {
        if case .number(let value) = self, value.isFinite {
            return Int(value)
        }
        return nil
    }

    /// Retrieves a double value if available.
    public var doubleValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }
}
