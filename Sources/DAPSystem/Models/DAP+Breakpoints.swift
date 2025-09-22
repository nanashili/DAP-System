//
//  DAPRuntimeModels+Breakpoints.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Design notes:
//  - All models are @frozen value types with immutable (let) fields for thread-safety and
//    predictable copies under Sendable.
//  - JSON emission pre-reserves dictionary capacity and uses static key storage to avoid
//    repeated string allocations and hashing.
//  - Inline helpers avoid branches and temporary arrays where possible.
//  - Parsers fail fast with tight guards, no intermediate Codable layer, to keep latency low.
//

import Foundation

// MARK: - Internal Perf Helpers

@usableFromInline
enum _J {
    // Static keys live once for the process lifetime. No re-allocation.
    static let line = "line"
    static let column = "column"
    static let endLine = "endLine"
    static let endColumn = "endColumn"
    static let id = "id"
    static let verified = "verified"
    static let message = "message"
    static let source = "source"
    static let instructionReference = "instructionReference"
    static let offset = "offset"
    static let reason = "reason"
    static let condition = "condition"
    static let hitCondition = "hitCondition"
    static let logMessage = "logMessage"
    static let mode = "mode"
    static let name = "name"
    static let names = "names"
    static let negate = "negate"
    static let path = "path"
    static let breakMode = "breakMode"
    static let filterId = "filterId"
    static let hex = "hex"
    static let kind = "kind"
    static let attributes = "attributes"
    static let visibility = "visibility"
    static let lazy = "lazy"
    static let value = "value"
    static let type = "type"
    static let presentationHint = "presentationHint"
    static let variablesReference = "variablesReference"
    static let namedVariables = "namedVariables"
    static let indexedVariables = "indexedVariables"
    static let memoryReference = "memoryReference"
    static let valueLocationReference = "valueLocationReference"
    static let dataId = "dataId"
    static let accessType = "accessType"
}

@inlinable

func _putIfNonEmpty(
    _ object: inout [String: DAPJSONValue],
    key: String,
    string: String?
) {
    if let s = string, !s.isEmpty { object[key] = .string(s) }
}

@inlinable

func _putIfSome<T>(
    _ object: inout [String: DAPJSONValue],
    key: String,
    number: T?
) where T: BinaryInteger {
    if let n = number { object[key] = .number(Double(n)) }
}

@inlinable

func _putIfSomeBool(
    _ object: inout [String: DAPJSONValue],
    key: String,
    value: Bool?
) {
    if let v = value { object[key] = .bool(v) }
}

// MARK: - Data Brekapoint

/// A data breakpoint watches a memory location or runtime object identity.
/// `dataId` is adapter-defined (e.g., memory address, object handle).
@frozen
public struct DAPDataBreakpoint: Sendable, Equatable {
    /// Adapter-defined identifier for the watched data location.
    public let dataId: String
    /// Optional access filter (e.g., "read", "write", "readWrite"); adapter-defined.
    public let accessType: String?
    /// Boolean expression that must evaluate to true to trigger.
    public let condition: String?
    /// Hit count condition (e.g., ">= 5"); adapter-defined grammar.
    public let hitCondition: String?

    @inlinable
    public init(
        dataId: String,
        accessType: String? = nil,
        condition: String? = nil,
        hitCondition: String? = nil
    ) {
        self.dataId = dataId
        self.accessType = accessType
        self.condition = condition
        self.hitCondition = hitCondition
    }

    /// Minimal-allocation JSON builder. Emits only non-empty optionals.
    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 4)
        object[_J.dataId] = .string(dataId)
        _putIfNonEmpty(&object, key: _J.accessType, string: accessType)
        _putIfNonEmpty(&object, key: _J.condition, string: condition)
        _putIfNonEmpty(&object, key: _J.hitCondition, string: hitCondition)
        return .object(object)
    }
}

/// Adapter-reported verification/status for a data breakpoint after `setDataBreakpoints`.
@frozen
public struct DAPDataBreakpointStatus: Sendable, Equatable {
    /// Whether the adapter accepted the data breakpoint and will stop on it.
    public let verified: Bool
    /// Optional diagnostic message describing verification or rejection.
    public let message: String?
    /// Adapter-assigned stable identifier for the data breakpoint (if any).
    public let id: String?

    @inlinable
    public init(verified: Bool, message: String?, id: String?) {
        self.verified = verified
        self.message = message
        self.id = id
    }

    /// Tight, fail-fast parser. Avoids Codable for hot path latency.
    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json, let v = o[_J.verified]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Data breakpoint response missing verification state"
            )
        }
        self.init(
            verified: v,
            message: o[_J.message]?.stringValue,
            id: o[_J.id]?.stringValue
        )
    }
}

// MARK: - Source Breakpoints

/// A source-code breakpoint in a file/line/column context.
/// Only non-empty optional fields are serialized to keep payloads small.
@frozen
public struct DAPSourceBreakpoint: Sendable, Equatable {
    /// 1-based line number where the breakpoint is set. Required by DAP.
    public let line: Int
    /// Optional 1-based column number. Some adapters ignore columns.
    public let column: Int?
    /// Boolean expression; hitting breakpoint requires this to evaluate to true.
    public let condition: String?
    /// Hit count condition (e.g., ">= 5", "== 3"). Adapter-specific grammar.
    public let hitCondition: String?
    /// Logpoint message template (supports `{var}` substitutions per adapter).
    public let logMessage: String?
    /// Adapter-specific mode (e.g., "debuggerLog", "trace"). Optional.
    public let mode: String?

    @inlinable
    public init(
        line: Int,
        column: Int? = nil,
        condition: String? = nil,
        hitCondition: String? = nil,
        logMessage: String? = nil,
        mode: String? = nil
    ) {
        self.line = line
        self.column = column
        self.condition = condition
        self.hitCondition = hitCondition
        self.logMessage = logMessage
        self.mode = mode
    }

    /// Minimal-allocation JSON builder.
    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 6)
        object[_J.line] = .number(Double(line))
        _putIfSome(&object, key: _J.column, number: column)
        _putIfNonEmpty(&object, key: _J.condition, string: condition)
        _putIfNonEmpty(&object, key: _J.hitCondition, string: hitCondition)
        _putIfNonEmpty(&object, key: _J.logMessage, string: logMessage)
        _putIfNonEmpty(&object, key: _J.mode, string: mode)
        return .object(object)
    }
}

// MARK: - Function Breakpoints

/// A function breakpoint identified by fully-qualified name per adapter semantics.
@frozen
public struct DAPFunctionBreakpoint: Sendable, Equatable {
    /// Function identifier (e.g., "MyModule.Type.method").
    public let name: String
    public let condition: String?
    public let hitCondition: String?
    public let logMessage: String?

    @inlinable
    public init(
        name: String,
        condition: String? = nil,
        hitCondition: String? = nil,
        logMessage: String? = nil
    ) {
        self.name = name
        self.condition = condition
        self.hitCondition = hitCondition
        self.logMessage = logMessage
    }

    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 4)
        object[_J.name] = .string(name)
        _putIfNonEmpty(&object, key: _J.condition, string: condition)
        _putIfNonEmpty(&object, key: _J.hitCondition, string: hitCondition)
        _putIfNonEmpty(&object, key: _J.logMessage, string: logMessage)
        return .object(object)
    }
}

// MARK: - Instruction Breakpoints

/// An instruction pointer / address breakpoint (for disassembly views).
@frozen
public struct DAPInstructionBreakpoint: Sendable, Equatable {
    /// Adapter-defined address reference (e.g., memory address or symbol).
    public let instructionReference: String
    /// Optional byte offset relative to `instructionReference`.
    public let offset: Int?
    public let condition: String?
    public let hitCondition: String?

    @inlinable
    public init(
        instructionReference: String,
        offset: Int? = nil,
        condition: String? = nil,
        hitCondition: String? = nil
    ) {
        self.instructionReference = instructionReference
        self.offset = offset
        self.condition = condition
        self.hitCondition = hitCondition
    }
    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 4)
        object[_J.instructionReference] = .string(instructionReference)
        _putIfSome(&object, key: _J.offset, number: offset)
        _putIfNonEmpty(&object, key: _J.condition, string: condition)
        _putIfNonEmpty(&object, key: _J.hitCondition, string: hitCondition)
        return .object(object)
    }
}

// MARK: - Breakpoint (Reported by Adapter)

/// Adapter-reported canonical breakpoint state (e.g., after setBreakpoints).
@frozen
public struct DAPBreakpoint: Sendable, Equatable {
    /// Stable adapter-level ID (if provided).
    public let id: Int?
    /// Whether the adapter validated the breakpoint and will stop execution on it.
    public let verified: Bool
    /// Optional message describing verification or rejection.
    public let message: String?
    /// Source descriptor for the location (may be absent for instruction BPs).
    public let source: DAPSource?
    /// 1-based start line/column.
    public let line: Int?
    public let column: Int?
    /// Optional end range for multi-token spans.
    public let endLine: Int?
    public let endColumn: Int?
    /// Machine-level reference and offset for instruction breakpoints.
    public let instructionReference: String?
    public let offset: Int?
    /// Optional reason string (adapter-defined) for changes in verification.
    public let reason: String?

    @inlinable
    public init(
        id: Int?,
        verified: Bool,
        message: String?,
        source: DAPSource?,
        line: Int?,
        column: Int?,
        endLine: Int?,
        endColumn: Int?,
        instructionReference: String?,
        offset: Int?,
        reason: String?
    ) {
        self.id = id
        self.verified = verified
        self.message = message
        self.source = source
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
        self.instructionReference = instructionReference
        self.offset = offset
        self.reason = reason
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json, let ver = o[_J.verified]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Breakpoint payload missing required fields"
            )
        }

        let src: DAPSource?
        if let v = o[_J.source] {
            src = try DAPSource(json: v)
        } else {
            src = nil
        }

        self.init(
            id: o[_J.id]?.intValue,
            verified: ver,
            message: o[_J.message]?.stringValue,
            source: src,
            line: o[_J.line]?.intValue,
            column: o[_J.column]?.intValue,
            endLine: o[_J.endLine]?.intValue,
            endColumn: o[_J.endColumn]?.intValue,
            instructionReference: o[_J.instructionReference]?.stringValue,
            offset: o[_J.offset]?.intValue,
            reason: o[_J.reason]?.stringValue
        )
    }
}

// MARK: - Breakpoint Location

/// A concrete location where a breakpoint can be set (e.g., from `breakpointLocations`).
@frozen
public struct DAPBreakpointLocation: Sendable, Equatable {
    public let line: Int
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?

    @inlinable
    public init(
        line: Int,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json, let line = o[_J.line]?.intValue else {
            throw DAPError.invalidResponse(
                "BreakpointLocation payload missing line"
            )
        }
        self.init(
            line: line,
            column: o[_J.column]?.intValue,
            endLine: o[_J.endLine]?.intValue,
            endColumn: o[_J.endColumn]?.intValue
        )
    }
}

// MARK: - Exception Options

/// DAP-defined exception break modes.
public enum DAPExceptionBreakMode: String, Sendable {
    case never, always, unhandled, userUnhandled
}

/// A segment of an exception type path (hierarchical exception identifiers).
@frozen
public struct DAPExceptionPathSegment: Sendable, Equatable {
    /// Ordered names forming a path component; semantics are adapter-defined.
    public let names: [String]
    /// If true, treat this path as a negative match.
    public let negate: Bool?

    @inlinable
    public init(names: [String], negate: Bool? = nil) {
        self.names = names
        self.negate = negate
    }

    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 2)
        object[_J.names] = .array(names.map(DAPJSONValue.string))
        _putIfSomeBool(&object, key: _J.negate, value: negate)
        return .object(object)
    }
}

/// Exception break configuration entry.
@frozen
public struct DAPExceptionOption: Sendable, Equatable {
    /// Hierarchical match path (optional).
    public let path: [DAPExceptionPathSegment]?
    /// Break behavior.
    public let breakMode: DAPExceptionBreakMode

    @inlinable
    public init(
        path: [DAPExceptionPathSegment]? = nil,
        breakMode: DAPExceptionBreakMode
    ) {
        self.path = path
        self.breakMode = breakMode
    }

    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 2)
        object[_J.breakMode] = .string(breakMode.rawValue)
        if let path, !path.isEmpty {
            object[_J.path] = .array(path.map { $0.jsonValue() })
        }
        return .object(object)
    }
}

/// Filter toggles for exception categories defined by the adapter.
@frozen
public struct DAPExceptionFilterOption: Sendable, Equatable {
    public let filterId: String
    public let condition: String?
    public let mode: String?

    @inlinable
    public init(filterId: String, condition: String? = nil, mode: String? = nil)
    {
        self.filterId = filterId
        self.condition = condition
        self.mode = mode
    }

    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 3)
        object[_J.filterId] = .string(filterId)
        _putIfNonEmpty(&object, key: _J.condition, string: condition)
        _putIfNonEmpty(&object, key: _J.mode, string: mode)
        return .object(object)
    }
}

// MARK: - Value/Variable Formatting

/// Optional formatting hints for numeric rendering (e.g., hex).
@frozen
public struct DAPValueFormat: Sendable, Equatable {
    public let hex: Bool?

    @inlinable
    public init(hex: Bool? = nil) { self.hex = hex }

    public func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = .init(minimumCapacity: 1)
        _putIfSomeBool(&object, key: _J.hex, value: hex)
        return .object(object)
    }
}

/// UI hint for variables in the tree (kind/visibility/attributes).
@frozen
public struct DAPVariablePresentationHint: Sendable, Equatable {
    public let kind: String?
    public let attributes: [String]?
    public let visibility: String?
    public let isLazy: Bool?

    @inlinable
    public init(
        kind: String? = nil,
        attributes: [String]? = nil,
        visibility: String? = nil,
        isLazy: Bool? = nil
    ) {
        self.kind = kind
        self.attributes = attributes
        self.visibility = visibility
        self.isLazy = isLazy
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json else {
            throw DAPError.invalidResponse(
                "VariablePresentationHint must be an object"
            )
        }
        let attrs = o[_J.attributes]?.arrayValue?.compactMap { $0.stringValue }
        self.init(
            kind: o[_J.kind]?.stringValue,
            attributes: attrs,
            visibility: o[_J.visibility]?.stringValue,
            isLazy: o[_J.lazy]?.boolValue
        )
    }
}

// MARK: - Set Expression / Variable Results

/// Result of `setExpression` including presentation and child refs.
@frozen
public struct DAPSetExpressionResult: Sendable, Equatable {
    public let value: String
    public let type: String?
    public let presentationHint: DAPVariablePresentationHint?
    public let variablesReference: Int?
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let memoryReference: String?
    public let valueLocationReference: Int?

    @inlinable
    public init(
        value: String,
        type: String?,
        presentationHint: DAPVariablePresentationHint?,
        variablesReference: Int?,
        namedVariables: Int?,
        indexedVariables: Int?,
        memoryReference: String?,
        valueLocationReference: Int?
    ) {
        self.value = value
        self.type = type
        self.presentationHint = presentationHint
        self.variablesReference = variablesReference
        self.namedVariables = namedVariables
        self.indexedVariables = indexedVariables
        self.memoryReference = memoryReference
        self.valueLocationReference = valueLocationReference
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json, let val = o[_J.value]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "setExpression response missing 'value'"
            )
        }
        let hint: DAPVariablePresentationHint? = {
            if let hv = o[_J.presentationHint] {
                return try? DAPVariablePresentationHint(json: hv)
            }
            return nil
        }()
        self.init(
            value: val,
            type: o[_J.type]?.stringValue,
            presentationHint: hint,
            variablesReference: o[_J.variablesReference]?.intValue,
            namedVariables: o[_J.namedVariables]?.intValue,
            indexedVariables: o[_J.indexedVariables]?.intValue,
            memoryReference: o[_J.memoryReference]?.stringValue,
            valueLocationReference: o[_J.valueLocationReference]?.intValue
        )
    }
}

/// Result of `setVariable` (subset of setExpression result).
@frozen
public struct DAPSetVariableResult: Sendable, Equatable {
    public let value: String
    public let type: String?
    public let variablesReference: Int?
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let memoryReference: String?
    public let valueLocationReference: Int?

    @inlinable
    public init(
        value: String,
        type: String?,
        variablesReference: Int?,
        namedVariables: Int?,
        indexedVariables: Int?,
        memoryReference: String?,
        valueLocationReference: Int?
    ) {
        self.value = value
        self.type = type
        self.variablesReference = variablesReference
        self.namedVariables = namedVariables
        self.indexedVariables = indexedVariables
        self.memoryReference = memoryReference
        self.valueLocationReference = valueLocationReference
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json, let val = o[_J.value]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "setVariable response missing 'value'"
            )
        }
        self.init(
            value: val,
            type: o[_J.type]?.stringValue,
            variablesReference: o[_J.variablesReference]?.intValue,
            namedVariables: o[_J.namedVariables]?.intValue,
            indexedVariables: o[_J.indexedVariables]?.intValue,
            memoryReference: o[_J.memoryReference]?.stringValue,
            valueLocationReference: o[_J.valueLocationReference]?.intValue
        )
    }
}
