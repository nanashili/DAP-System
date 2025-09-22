//
//  DAPJSON.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Goals
//  -----
//  • Keep the enum shape stable for Sendable/Equatable and Codable interop.
//  • Avoid unnecessary allocations and dynamic dispatch on hot paths.
//  • Provide predictable, documented accessors for common scalar/int/array/object use.
//  • Add small, zero-magic utilities (builders, subscripts, pointer lookup).
//

import Foundation

/// A compact, type-safe representation of arbitrary JSON payloads exchanged with DAP adapters.
/// The enum is frozen for ABI stability and is `Sendable` to safely cross actors/threads.
@frozen
public enum DAPJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)  // Chosen for wire-compat; use `intValue` / `intExact` helpers as needed.
    case string(String)
    case array([DAPJSONValue])
    case object([String: DAPJSONValue])
}

// MARK: - Codable (hand-rolled, fast path)

extension DAPJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        // Single-value decoding avoids intermediate containers when possible.
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([DAPJSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: DAPJSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - Scalar Accessors (inlinable, branch-light)

extension DAPJSONValue {
    /// Returns the string if `.string`, else `nil`. No conversions or copies.
    @inlinable public var stringValue: String? {
        if case .string(let v) = self { v } else { nil }
    }

    /// Returns the bool if `.bool`, else `nil`.
    @inlinable public var boolValue: Bool? {
        if case .bool(let v) = self { v } else { nil }
    }

    /// Returns the dictionary if `.object`, else `nil`. Shares CoW storage.
    @inlinable public var objectValue: [String: DAPJSONValue]? {
        if case .object(let v) = self { v } else { nil }
    }

    /// Returns the array if `.array`, else `nil`. Shares CoW storage.
    @inlinable public var arrayValue: [DAPJSONValue]? {
        if case .array(let v) = self { v } else { nil }
    }

    /// Returns an `Int` if `.number` is finite. Uses truncating cast (JSON has no int type).
    @inlinable public var intValue: Int? {
        if case .number(let d) = self, d.isFinite { return Int(d) }
        return nil
    }

    /// Returns the `Double` if `.number`.
    @inlinable public var doubleValue: Double? {
        if case .number(let d) = self { d } else { nil }
    }

    /// Returns an exact integer if `.number` holds an integral value in range (no precision loss).
    @inlinable public var intExact: Int? {
        guard case .number(let d) = self, d.isFinite else { return nil }
        let i = Int(d)
        return d == Double(i) ? i : nil
    }
}

// MARK: - Object / Array Subscripts (developer ergonomics)

extension DAPJSONValue {
    /// Object member access. Returns `nil` if not an object or key is missing.
    @inlinable public subscript(key key: String) -> DAPJSONValue? {
        get { objectValue?[key] }
    }

    /// Array index access. Returns `nil` if not an array or out-of-bounds.
    @inlinable public subscript(index index: Int) -> DAPJSONValue? {
        get {
            guard case .array(let arr) = self, index >= 0, index < arr.count
            else { return nil }
            return arr[index]
        }
    }

    /// Convenience chaining: `json["a","b","c"]` walks nested objects (not arrays).
    /// Returns first missing link as `nil`.
    @inlinable public subscript(path keys: String...) -> DAPJSONValue? {
        var cur: DAPJSONValue? = self
        for k in keys {
            guard case .object(let o)? = cur, let next = o[k] else {
                return nil
            }
            cur = next
        }
        return cur
    }
}

// MARK: - Builders (minimal overhead, predictable capacity)

extension DAPJSONValue {
    /// Creates `.object` with `minimumCapacity` to avoid rehashing on hot paths.
    @inlinable public static func makeObject(capacity: Int = 0) -> DAPJSONValue
    {
        .object(Dictionary(minimumCapacity: max(0, capacity)))
    }

    /// Creates `.array` with `reserveCapacity` to avoid growth during `append`.
    @inlinable public static func makeArray(capacity: Int = 0) -> DAPJSONValue {
        var arr: [DAPJSONValue] = []
        if capacity > 0 { arr.reserveCapacity(capacity) }
        return .array(arr)
    }

    /// Returns a new `.object` by inserting a key/value into an existing `.object` (copy-on-write).
    @inlinable public func settingObjectKey(
        _ key: String,
        to value: DAPJSONValue
    ) -> DAPJSONValue {
        guard case .object(var o) = self else { return self }
        o[key] = value
        return .object(o)
    }

    /// Returns a new `.array` by appending `value` (copy-on-write).
    @inlinable public func appendingArrayValue(_ value: DAPJSONValue)
        -> DAPJSONValue
    {
        guard case .array(var a) = self else { return self }
        a.append(value)
        return .array(a)
    }
}

// MARK: - JSON Pointer (RFC 6901) – tiny helper, non-validating

extension DAPJSONValue {
    /// Resolves a simple JSON Pointer (e.g., "/a/b/0"). No escaping support for `~0`/`~1` to keep it lean.
    /// Returns `nil` if any segment is missing or types don't match the path.
    @inlinable public func value(atPointer pointer: String) -> DAPJSONValue? {
        guard pointer.first == "/" else { return nil }
        // Cheap split without regex/alloc heavy operations.
        var current: DAPJSONValue = self
        var start = pointer.index(after: pointer.startIndex)
        while start <= pointer.endIndex {
            let end = pointer[start...].firstIndex(of: "/") ?? pointer.endIndex
            let segment = String(pointer[start..<end])
            if case .object(let o) = current, let v = o[segment] {
                current = v
            } else if case .array(let a) = current, let i = Int(segment),
                i >= 0, i < a.count
            {
                current = a[i]
            } else {
                return nil
            }
            if end == pointer.endIndex { break }
            start = pointer.index(after: end)
        }
        return current
    }
}

// MARK: - Foundation Bridging (optional, zero-surprise)

extension DAPJSONValue {
    /// Converts to a Foundation JSON object suitable for `JSONSerialization`.
    /// Uses value semantics; arrays/dicts remain CoW until mutated.
    @inlinable public func toFoundation() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.toFoundation() }
        case .object(let o): return o.mapValues { $0.toFoundation() }
        }
    }

    /// Best-effort initializer from Foundation JSON (`JSONSerialization.jsonObject` output).
    /// Fails if encountering non-JSON types.
    @inlinable public init?(foundation: Any) {
        switch foundation {
        case is NSNull: self = .null
        case let b as Bool: self = .bool(b)
        case let n as NSNumber:
            // Distinguish booleans (NSNumber can box Bool). We already matched Bool above, so treat as number.
            self = .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let arr as [Any]:
            var out: [DAPJSONValue] = []
            out.reserveCapacity(arr.count)
            for e in arr {
                guard let v = DAPJSONValue(foundation: e) else { return nil }
                out.append(v)
            }
            self = .array(out)
        case let dict as [String: Any]:
            var out = [String: DAPJSONValue](minimumCapacity: dict.count)
            for (k, v) in dict {
                guard let jv = DAPJSONValue(foundation: v) else { return nil }
                out[k] = jv
            }
            self = .object(out)
        default:
            return nil
        }
    }

    /// Encodes as `Data` using `JSONSerialization` (fast, no model reflection).
    @inlinable public func data(prettyPrinted: Bool = false) throws -> Data {
        let opts: JSONSerialization.WritingOptions =
            prettyPrinted ? [.prettyPrinted] : []
        return try JSONSerialization.data(
            withJSONObject: toFoundation(),
            options: opts
        )
    }
}

// MARK: - Small convenience constants

extension DAPJSONValue {
    /// Common singletons to avoid re-allocating literals at callsites.
    public static let `true`: DAPJSONValue = .bool(true)
    public static let `false`: DAPJSONValue = .bool(false)
    public static let emptyObject: DAPJSONValue = .object([:])
    public static let emptyArray: DAPJSONValue = .array([])
}
