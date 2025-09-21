//
//  DAPRuntimeModels.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

public struct DAPSource: Sendable, Equatable {
    public let name: String?
    public let path: URL?
    public let sourceReference: Int?

    public init(name: String?, path: URL?, sourceReference: Int?) {
        self.name = name
        self.path = path
        self.sourceReference = sourceReference
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json else {
            throw DAPError.invalidResponse("Source payload must be an object")
        }

        let name = object["name"]?.stringValue
        let path: URL?
        if let pathString = object["path"]?.stringValue {
            path = URL(fileURLWithPath: pathString)
        } else {
            path = nil
        }

        let sourceReference = object["sourceReference"]?.intValue

        self.init(name: name, path: path, sourceReference: sourceReference)
    }
}

public struct DAPThread: Sendable, Equatable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let id = object["id"]?.intValue,
            let name = object["name"]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "Thread payload missing required fields"
            )
        }

        self.init(id: id, name: name)
    }
}

public struct DAPStackFrame: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let source: DAPSource?
    public let line: Int
    public let column: Int
    public let endLine: Int?
    public let endColumn: Int?

    public init(
        id: Int,
        name: String,
        source: DAPSource?,
        line: Int,
        column: Int,
        endLine: Int?,
        endColumn: Int?
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let id = object["id"]?.intValue,
            let name = object["name"]?.stringValue,
            let line = object["line"]?.intValue,
            let column = object["column"]?.intValue
        else {
            throw DAPError.invalidResponse(
                "Stack frame payload missing required fields"
            )
        }

        let source: DAPSource?
        if let sourceValue = object["source"] {
            source = try DAPSource(json: sourceValue)
        } else {
            source = nil
        }

        let endLine = object["endLine"]?.intValue
        let endColumn = object["endColumn"]?.intValue

        self.init(
            id: id,
            name: name,
            source: source,
            line: line,
            column: column,
            endLine: endLine,
            endColumn: endColumn
        )
    }
}

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
        guard case .object(let object) = json,
            let name = object["name"]?.stringValue,
            let variablesReference = object["variablesReference"]?.intValue,
            let expensive = object["expensive"]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Scope payload missing required fields"
            )
        }

        let source: DAPSource?
        if let sourceValue = object["source"] {
            source = try DAPSource(json: sourceValue)
        } else {
            source = nil
        }

        self.init(
            name: name,
            variablesReference: variablesReference,
            expensive: expensive,
            presentationHint: object["presentationHint"]?.stringValue,
            namedVariables: object["namedVariables"]?.intValue,
            indexedVariables: object["indexedVariables"]?.intValue,
            source: source,
            line: object["line"]?.intValue,
            column: object["column"]?.intValue
        )
    }
}

public struct DAPVariable: Sendable, Equatable {
    public let name: String
    public let value: String
    public let type: String?
    public let variablesReference: Int
    public let namedVariables: Int?
    public let indexedVariables: Int?
    public let evaluateName: String?

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
        guard case .object(let object) = json,
            let name = object["name"]?.stringValue,
            let value = object["value"]?.stringValue,
            let variablesReference = object["variablesReference"]?.intValue
        else {
            throw DAPError.invalidResponse(
                "Variable payload missing required fields"
            )
        }

        self.init(
            name: name,
            value: value,
            type: object["type"]?.stringValue,
            variablesReference: variablesReference,
            namedVariables: object["namedVariables"]?.intValue,
            indexedVariables: object["indexedVariables"]?.intValue,
            evaluateName: object["evaluateName"]?.stringValue
        )
    }
}

public struct DAPStoppedEvent: Sendable, Equatable {
    public let reason: String
    public let description: String?
    public let threadId: Int?
    public let text: String?
    public let allThreadsStopped: Bool?

    public init(
        reason: String,
        description: String?,
        threadId: Int?,
        text: String?,
        allThreadsStopped: Bool?
    ) {
        self.reason = reason
        self.description = description
        self.threadId = threadId
        self.text = text
        self.allThreadsStopped = allThreadsStopped
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let reason = object["reason"]?.stringValue
        else {
            throw DAPError.invalidResponse("Stopped event missing reason")
        }

        self.init(
            reason: reason,
            description: object["description"]?.stringValue,
            threadId: object["threadId"]?.intValue,
            text: object["text"]?.stringValue,
            allThreadsStopped: object["allThreadsStopped"]?.boolValue
        )
    }
}

public struct DAPContinuedEvent: Sendable, Equatable {
    public let threadId: Int?
    public let allThreadsContinued: Bool?

    public init(threadId: Int?, allThreadsContinued: Bool?) {
        self.threadId = threadId
        self.allThreadsContinued = allThreadsContinued
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json else {
            throw DAPError.invalidResponse(
                "Continued event must include an object body"
            )
        }

        self.init(
            threadId: object["threadId"]?.intValue,
            allThreadsContinued: object["allThreadsContinued"]?.boolValue
        )
    }
}

public struct DAPTerminatedEvent: Sendable, Equatable {
    public let restart: Bool?

    public init(restart: Bool?) {
        self.restart = restart
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json else {
            throw DAPError.invalidResponse(
                "Terminated event must include an object body"
            )
        }

        self.init(restart: object["restart"]?.boolValue)
    }
}

public struct DAPOutputEvent: Sendable, Equatable {
    public let category: String?
    public let output: String
    public let variablesReference: Int?
    public let data: [String: DAPJSONValue]?

    public init(
        category: String?,
        output: String,
        variablesReference: Int?,
        data: [String: DAPJSONValue]?
    ) {
        self.category = category
        self.output = output
        self.variablesReference = variablesReference
        self.data = data
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let output = object["output"]?.stringValue
        else {
            throw DAPError.invalidResponse("Output event missing output text")
        }

        self.init(
            category: object["category"]?.stringValue,
            output: output,
            variablesReference: object["variablesReference"]?.intValue,
            data: object["data"]?.objectValue
        )
    }
}

public enum DAPSessionEvent: Sendable, Equatable {
    case initialized
    case stopped(DAPStoppedEvent)
    case continued(DAPContinuedEvent)
    case terminated(DAPTerminatedEvent)
    case output(DAPOutputEvent)
}

public struct DAPDataBreakpoint: Sendable, Equatable {
    public let dataId: String
    public let accessType: String?
    public let condition: String?
    public let hitCondition: String?

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

    func jsonValue() -> DAPJSONValue {
        var object: [String: DAPJSONValue] = [
            "dataId": .string(dataId)
        ]
        if let accessType {
            object["accessType"] = .string(accessType)
        }
        if let condition {
            object["condition"] = .string(condition)
        }
        if let hitCondition {
            object["hitCondition"] = .string(hitCondition)
        }
        return .object(object)
    }
}

public struct DAPDataBreakpointStatus: Sendable, Equatable {
    public let verified: Bool
    public let message: String?
    public let id: String?

    public init(verified: Bool, message: String?, id: String?) {
        self.verified = verified
        self.message = message
        self.id = id
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let verified = object["verified"]?.boolValue
        else {
            throw DAPError.invalidResponse(
                "Data breakpoint response missing verification state"
            )
        }

        self.init(
            verified: verified,
            message: object["message"]?.stringValue,
            id: object["id"]?.stringValue
        )
    }
}

public struct DAPLoadedSource: Sendable, Equatable {
    public let source: DAPSource

    public init(source: DAPSource) {
        self.source = source
    }

    init(json: DAPJSONValue) throws {
        self.init(source: try DAPSource(json: json))
    }
}

public struct DAPModule: Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: URL?
    public let symbolFilePath: URL?
    public let isOptimized: Bool?

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
        guard case .object(let object) = json,
            let idValue = object["id"],
            let name = object["name"]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "Module payload missing required fields"
            )
        }

        let id: String
        if let stringID = idValue.stringValue {
            id = stringID
        } else if let numberID = idValue.intValue {
            id = String(numberID)
        } else {
            throw DAPError.invalidResponse(
                "Module identifier must be a string or number"
            )
        }

        let path: URL?
        if let pathString = object["path"]?.stringValue {
            path = URL(fileURLWithPath: pathString)
        } else {
            path = nil
        }

        let symbolFilePath: URL?
        if let symbolPath = object["symbolFilePath"]?.stringValue {
            symbolFilePath = URL(fileURLWithPath: symbolPath)
        } else {
            symbolFilePath = nil
        }

        self.init(
            id: id,
            name: name,
            path: path,
            symbolFilePath: symbolFilePath,
            isOptimized: object["isOptimized"]?.boolValue
        )
    }
}

public struct DAPCompletionItem: Sendable, Equatable {
    public let label: String
    public let text: String?
    public let detail: String?
    public let type: String?

    public init(label: String, text: String?, detail: String?, type: String?) {
        self.label = label
        self.text = text
        self.detail = detail
        self.type = type
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let label = object["label"]?.stringValue
        else {
            throw DAPError.invalidResponse("Completion item missing label")
        }

        self.init(
            label: label,
            text: object["text"]?.stringValue
                ?? object["insertText"]?.stringValue,
            detail: object["detail"]?.stringValue,
            type: object["type"]?.stringValue
        )
    }
}

public struct DAPReadMemoryResult: Sendable, Equatable {
    public let address: String
    public let data: Data
    public let unreadableBytes: Int?

    public init(address: String, data: Data, unreadableBytes: Int?) {
        self.address = address
        self.data = data
        self.unreadableBytes = unreadableBytes
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let address = object["address"]?.stringValue,
            let dataString = object["data"]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "readMemory response missing address or data"
            )
        }

        guard let data = Data(base64Encoded: dataString) else {
            throw DAPError.invalidResponse(
                "readMemory response contains invalid base64 data"
            )
        }

        self.init(
            address: address,
            data: data,
            unreadableBytes: object["unreadableBytes"]?.intValue
        )
    }
}

public struct DAPWriteMemoryResult: Sendable, Equatable {
    public let bytesWritten: Int
    public let offset: Int?

    public init(bytesWritten: Int, offset: Int?) {
        self.bytesWritten = bytesWritten
        self.offset = offset
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let object) = json,
            let bytesWritten = object["bytesWritten"]?.intValue
        else {
            throw DAPError.invalidResponse(
                "writeMemory response missing bytesWritten"
            )
        }

        self.init(
            bytesWritten: bytesWritten,
            offset: object["offset"]?.intValue
        )
    }
}
