//
//  DAPAdvancedFeatures.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

public struct DAPConditionalBreakpoint: Codable, Hashable, Sendable {
    public let fileURL: URL
    public let line: Int
    public let condition: String
    public let hitCondition: String?
    public let logMessage: String?

    public init(
        fileURL: URL,
        line: Int,
        condition: String,
        hitCondition: String? = nil,
        logMessage: String? = nil
    ) {
        self.fileURL = fileURL
        self.line = line
        self.condition = condition
        self.hitCondition = hitCondition
        self.logMessage = logMessage
    }
}

public struct DAPWatchExpression: Codable, Hashable, Sendable {
    public let expression: String
    public let context: String

    public init(expression: String, context: String = "watch") {
        self.expression = expression
        self.context = context
    }
}

public struct DAPSessionMetadata: Codable, Sendable, Hashable {
    public let sessionID: UUID
    public let adapterIdentifier: String
    public let openedFiles: [URL]
    public let timestamp: Date
    public let configuration: [String: DAPJSONValue]

    public init(
        sessionID: UUID,
        adapterIdentifier: String,
        openedFiles: [URL],
        timestamp: Date,
        configuration: [String: DAPJSONValue]
    ) {
        self.sessionID = sessionID
        self.adapterIdentifier = adapterIdentifier
        self.openedFiles = openedFiles
        self.timestamp = timestamp
        self.configuration = configuration
    }

    public static func == (lhs: DAPSessionMetadata, rhs: DAPSessionMetadata)
        -> Bool
    {
        lhs.sessionID == rhs.sessionID
            && lhs.adapterIdentifier == rhs.adapterIdentifier
            && lhs.openedFiles == rhs.openedFiles
            && lhs.timestamp == rhs.timestamp
            && lhs.configuration == rhs.configuration
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(adapterIdentifier)
        hasher.combine(openedFiles)
        hasher.combine(timestamp)

        let encoder = JSONEncoder()
        encoder.outputFormatting.insert(.sortedKeys)
        if let data = try? encoder.encode(configuration) {
            hasher.combine(data)
        } else {
            hasher.combine(configuration.count)
        }
    }
}
