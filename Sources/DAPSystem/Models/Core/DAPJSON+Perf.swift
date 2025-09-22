//
//  DAPJSON+Perf.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@usableFromInline enum _J {
    // Static keys live once for the process lifetime. No re-allocation.
    static let id = "id"
    static let name = "name"
    static let path = "path"
    static let source = "source"
    static let sourceReference = "sourceReference"
    static let line = "line"
    static let column = "column"
    static let endLine = "endLine"
    static let endColumn = "endColumn"
    static let variablesReference = "variablesReference"
    static let namedVariables = "namedVariables"
    static let indexedVariables = "indexedVariables"
    static let expensive = "expensive"
    static let presentationHint = "presentationHint"
    static let evaluateName = "evaluateName"
    static let kind = "kind"
    static let label = "label"
    static let instructionPointerRef = "instructionPointerReference"
    static let verified = "verified"
    static let message = "message"
    static let reason = "reason"
    static let description = "description"
    static let threadId = "threadId"
    static let text = "text"
    static let allThreadsStopped = "allThreadsStopped"
    static let allThreadsContinued = "allThreadsContinued"
    static let restart = "restart"
    static let category = "category"
    static let output = "output"
    static let data = "data"
    static let type = "type"
    static let address = "address"
    static let unreadableBytes = "unreadableBytes"
    static let bytesWritten = "bytesWritten"
    static let offset = "offset"
    static let insertText = "insertText"
    static let detail = "detail"
    static let instructionReference = "instructionReference"
    static let condition = "condition"
    static let hitCondition = "hitCondition"
    static let logMessage = "logMessage"
    static let mode = "mode"
    static let names = "names"
    static let breakMode = "breakMode"
    static let hex = "hex"
    static let attributes = "attributes"
    static let lazy = "lazy"
    static let value = "value"
    static let dataId = "dataId"
    static let accessType = "accessType"
    static let negate = "negate"
    static let filterId = "filterId"
    static let visibility = "visibility"
    static let memoryReference = "memoryReference"
    static let valueLocationReference = "valueLocationReference"
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

@inlinable
func _putIfSomeInt(
    _ object: inout [String: DAPJSONValue],
    key: String,
    value: Int?
) {
    if let v = value { object[key] = .number(Double(v)) }
}
