//
//  DAPMessage.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//

import Foundation

public enum DAPMessageType: String, Codable, Sendable {
    case request
    case response
    case event
}

public protocol DAPAnyMessage: Codable, Sendable {
    var seq: Int { get }
    var type: DAPMessageType { get }
}

public struct DAPRequest: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    public let command: String
    public let arguments: DAPJSONValue?

    public init(seq: Int, command: String, arguments: DAPJSONValue?) {
        self.seq = seq
        self.type = .request
        self.command = command
        self.arguments = arguments
    }
}

public struct DAPResponse: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    public let requestSeq: Int
    public let success: Bool
    public let command: String
    public let message: String?
    public let body: DAPJSONValue?

    public init(
        seq: Int,
        requestSeq: Int,
        success: Bool,
        command: String,
        message: String?,
        body: DAPJSONValue?
    ) {
        self.seq = seq
        self.type = .response
        self.requestSeq = requestSeq
        self.success = success
        self.command = command
        self.message = message
        self.body = body
    }
}

public struct DAPEvent: DAPAnyMessage {
    public let seq: Int
    public let type: DAPMessageType
    public let event: String
    public let body: DAPJSONValue?

    public init(seq: Int, event: String, body: DAPJSONValue?) {
        self.seq = seq
        self.type = .event
        self.event = event
        self.body = body
    }
}

public enum DAPMessage: Sendable {
    case request(DAPRequest)
    case response(DAPResponse)
    case event(DAPEvent)

    public var seq: Int {
        switch self {
        case .request(let request):
            return request.seq
        case .response(let response):
            return response.seq
        case .event(let event):
            return event.seq
        }
    }
}

extension DAPMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DAPMessageType.self, forKey: .type)
        switch type {
        case .request:
            let request = try DAPRequest(from: decoder)
            self = .request(request)
        case .response:
            let response = try DAPResponse(from: decoder)
            self = .response(response)
        case .event:
            let event = try DAPEvent(from: decoder)
            self = .event(event)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let request):
            try request.encode(to: encoder)
        case .response(let response):
            try response.encode(to: encoder)
        case .event(let event):
            try event.encode(to: encoder)
        }
    }
}
