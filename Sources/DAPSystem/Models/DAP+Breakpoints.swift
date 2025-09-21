//
//  DAPRuntimeModels+Breakpoints.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

public struct DAPSourceBreakpoint: Sendable, Equatable {
    public let line: Int
    public let column: Int?
    public let condition: String?
    public let hitCondition: String?
    public let logMessage: String?
    public let mode: String?

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

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "line": .number(Double(line))
        ]
        if let column {
            object["column"] = .number(Double(column))
        }
        if let condition, !condition.isEmpty {
            object["condition"] = .string(condition)
        }
        if let hitCondition, !hitCondition.isEmpty {
            object["hitCondition"] = .string(hitCondition)
        }
        if let logMessage, !logMessage.isEmpty {
            object["logMessage"] = .string(logMessage)
        }
        if let mode, !mode.isEmpty {
            object["mode"] = .string(mode)
        }
        return .object(object)
    }
}

public struct DAPFunctionBreakpoint: Sendable, Equatable {
    public let name: String
    public let condition: String?
    public let hitCondition: String?
    public let logMessage: String?

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

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "name": .string(name)
        ]
        if let condition, !condition.isEmpty {
            object["condition"] = .string(condition)
        }
        if let hitCondition, !hitCondition.isEmpty {
            object["hitCondition"] = .string(hitCondition)
        }
        if let logMessage, !logMessage.isEmpty {
            object["logMessage"] = .string(logMessage)
        }
        return .object(object)
    }
}

public struct DAPInstructionBreakpoint: Sendable, Equatable {
    public let instructionReference: String
    public let offset: Int?
    public let condition: String?
    public let hitCondition: String?

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

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "instructionReference": .string(instructionReference)
        ]
        if let offset {
            object["offset"] = .number(Double(offset))
        }
        if let condition, !condition.isEmpty {
            object["condition"] = .string(condition)
        }
        if let hitCondition, !hitCondition.isEmpty {
            object["hitCondition"] = .string(hitCondition)
        }
        return .object(object)
    }
}

public struct DAPBreakpoint: Sendable, Equatable {
    public let id: Int?
    public let verified: Bool
    public let message: String?
    public let source: DAPSource?
    public let line: Int?
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?
    public let instructionReference: String?
    public let offset: Int?
    public let reason: String?

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
        guard case .object(let object) = json,
            let verified = object["verified"]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Breakpoint payload missing required fields"
            )
        }

        let source: DAPSource?
        if let sourceValue = object["source"] {
            source = try DAPSource(json: sourceValue)
        } else {
            source = nil
        }

        self.init(
            id: object["id"]?.intValue,
            verified: verified,
            message: object["message"]?.stringValue,
            source: source,
            line: object["line"]?.intValue,
            column: object["column"]?.intValue,
            endLine: object["endLine"]?.intValue,
            endColumn: object["endColumn"]?.intValue,
            instructionReference: object["instructionReference"]?.stringValue,
            offset: object["offset"]?.intValue,
            reason: object["reason"]?.stringValue
        )
    }
}

public struct DAPBreakpointLocation: Sendable, Equatable {
    public let line: Int
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?

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
        guard case .object(let object) = json,
            let line = object["line"]?.intValue
        else {
            throw DAPError.invalidResponse(
                "BreakpointLocation payload missing line"
            )
        }

        self.init(
            line: line,
            column: object["column"]?.intValue,
            endLine: object["endLine"]?.intValue,
            endColumn: object["endColumn"]?.intValue
        )
    }
}

public enum DAPExceptionBreakMode: String, Sendable {
    case never
    case always
    case unhandled
    case userUnhandled
}

public struct DAPExceptionPathSegment: Sendable, Equatable {
    public let names: [String]
    public let negate: Bool?

    public init(names: [String], negate: Bool? = nil) {
        self.names = names
        self.negate = negate
    }

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "names": .array(names.map { .string($0) })
        ]
        if let negate {
            object["negate"] = .bool(negate)
        }
        return .object(object)
    }
}

public struct DAPExceptionOption: Sendable, Equatable {
    public let path: [DAPExceptionPathSegment]?
    public let breakMode: DAPExceptionBreakMode

    public init(
        path: [DAPExceptionPathSegment]? = nil,
        breakMode: DAPExceptionBreakMode
    ) {
        self.path = path
        self.breakMode = breakMode
    }

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "breakMode": .string(breakMode.rawValue)
        ]
        if let path, !path.isEmpty {
            object["path"] = .array(path.map { $0.jsonValue() })
        }
        return .object(object)
    }
}

public struct DAPExceptionFilterOption: Sendable, Equatable {
    public let filterId: String
    public let condition: String?
    public let mode: String?

    public init(
        filterId: String,
        condition: String? = nil,
        mode: String? = nil
    ) {
        self.filterId = filterId
        self.condition = condition
        self.mode = mode
    }

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "filterId": .string(filterId)
        ]
        if let condition, !condition.isEmpty {
            object["condition"] = .string(condition)
        }
        if let mode, !mode.isEmpty {
            object["mode"] = .string(mode)
        }
        return .object(object)
    }
}

public struct DAPValueFormat: Sendable, Equatable {
    public let hex: Bool?

    public init(hex: Bool? = nil) {
        self.hex = hex
    }

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [:]
        if let hex {
            object["hex"] = .bool(hex)
        }
        return .object(object)
    }
}

public struct DAPVariablePresentationHint: Sendable, Equatable {
    public let kind: String?
    public let attributes: [String]?
    public let visibility: String?
    public let isLazy: Bool?

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
        guard case .object(let object) = json else {
            throw DAPError.invalidResponse(
                "VariablePresentationHint must be an object"
            )
        }

        let attributes = object["attributes"]?.arrayValue?.compactMap {
            $0.stringValue
        }

        self.init(
            kind: object["kind"]?.stringValue,
            attributes: attributes,
            visibility: object["visibility"]?.stringValue,
            isLazy: object["lazy"]?.boolValue
        )
    }
}

public struct DAPSetExpressionResult: Sendable, Equatable {
    public let value: String
    public let type: String?
    public let presentationHint: DAPVariablePresentationHint?
    public let variablesReference: Int?
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let memoryReference: String?
    public let valueLocationReference: Int?

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
        guard case .object(let object) = json,
            let value = object["value"]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "setExpression response missing 'value'"
            )
        }

        let presentationHint: DAPVariablePresentationHint?
        if let hintValue = object["presentationHint"] {
            presentationHint = try DAPVariablePresentationHint(json: hintValue)
        } else {
            presentationHint = nil
        }

        self.init(
            value: value,
            type: object["type"]?.stringValue,
            presentationHint: presentationHint,
            variablesReference: object["variablesReference"]?.intValue,
            namedVariables: object["namedVariables"]?.intValue,
            indexedVariables: object["indexedVariables"]?.intValue,
            memoryReference: object["memoryReference"]?.stringValue,
            valueLocationReference: object["valueLocationReference"]?.intValue
        )
    }
}

public struct DAPSetVariableResult: Sendable, Equatable {
    public let value: String
    public let type: String?
    public let variablesReference: Int?
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let memoryReference: String?
    public let valueLocationReference: Int?

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
        guard case .object(let object) = json,
            let value = object["value"]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "setVariable response missing 'value'"
            )
        }

        self.init(
            value: value,
            type: object["type"]?.stringValue,
            variablesReference: object["variablesReference"]?.intValue,
            namedVariables: object["namedVariables"]?.intValue,
            indexedVariables: object["indexedVariables"]?.intValue,
            memoryReference: object["memoryReference"]?.stringValue,
            valueLocationReference: object["valueLocationReference"]?.intValue
        )
    }
}
