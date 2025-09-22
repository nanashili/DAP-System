//
//  DAPCompletionItem.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPCompletionItem: Sendable, Equatable {
    public let label: String
    /// The actual text to insert; uses `insertText` if present, falling back to `text`.
    public let text: String?
    public let detail: String?
    public let type: String?

    @inlinable
    public init(label: String, text: String?, detail: String?, type: String?) {
        self.label = label
        self.text = text
        self.detail = detail
        self.type = type
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let label = o[_J.label]?.stringValue
        else {
            throw DAPError.invalidResponse("Completion item missing label")
        }
        self.init(
            label: label,
            text: o[_J.insertText]?.stringValue ?? o["text"]?.stringValue,
            detail: o[_J.detail]?.stringValue,
            type: o[_J.type]?.stringValue
        )
    }
}
