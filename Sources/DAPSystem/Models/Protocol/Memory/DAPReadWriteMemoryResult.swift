//
//  DAPReadMemoryResult.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 9/22/25.
//

import Foundation

@frozen
public struct DAPReadMemoryResult: Sendable, Equatable {
    public let address: String
    public let data: Data
    public let unreadableBytes: Int?

    @inlinable
    public init(address: String, data: Data, unreadableBytes: Int?) {
        self.address = address
        self.data = data
        self.unreadableBytes = unreadableBytes
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let addr = o[_J.address]?.stringValue,
            let base64 = o[_J.data]?.stringValue
        else {
            throw DAPError.invalidResponse(
                "readMemory response missing address or data"
            )
        }
        // Ignore unknown characters to be tolerant of adapters adding whitespace.
        guard
            let bytes = Data(
                base64Encoded: base64,
                options: .ignoreUnknownCharacters
            )
        else {
            throw DAPError.invalidResponse(
                "readMemory response contains invalid base64 data"
            )
        }
        self.init(
            address: addr,
            data: bytes,
            unreadableBytes: o[_J.unreadableBytes]?.intValue
        )
    }
}

@frozen
public struct DAPWriteMemoryResult: Sendable, Equatable {
    public let bytesWritten: Int
    public let offset: Int?

    @inlinable
    public init(bytesWritten: Int, offset: Int?) {
        self.bytesWritten = bytesWritten
        self.offset = offset
    }

    init(json: DAPJSONValue) throws {
        guard case .object(let o) = json,
            let count = o[_J.bytesWritten]?.intValue
        else {
            throw DAPError.invalidResponse(
                "writeMemory response missing bytesWritten"
            )
        }
        self.init(bytesWritten: count, offset: o[_J.offset]?.intValue)
    }
}
