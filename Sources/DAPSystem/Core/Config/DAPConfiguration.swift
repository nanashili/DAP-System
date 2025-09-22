//
//  DAPConfiguration.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  - Defines DAP adapter manifests, field schema, and configuration validation.
//  - Loads, validates, and hot-watches manifests directory for changes.
//  - All models are Codable and Sendable; manifests can be JSON or plist arrays.
//

import Darwin
import Dispatch
import Foundation

// MARK: - Manifest Schema Types

public struct DAPAdapterCapability: Codable, Hashable, Sendable {
    public let name: String
    public let description: String
    public let isRequired: Bool
}

public struct DAPAdapterConfigurationField: Codable, Sendable {
    public enum FieldType: String, Codable, Sendable {
        case text, password, toggle, selection, number
    }

    public let key: String
    public let title: String
    public let type: FieldType
    public let defaultValue: DAPJSONValue?
    public let description: String?
    public let options: [String]?

    public init(
        key: String,
        title: String,
        type: FieldType,
        defaultValue: DAPJSONValue? = nil,
        description: String? = nil,
        options: [String]? = nil
    ) {
        self.key = key
        self.title = title
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
        self.options = options
    }
}

public struct DAPRuntimeIdentifier: RawRepresentable, Codable, Hashable,
    Sendable
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let embedded = DAPRuntimeIdentifier("embedded")
    public static let externalProcess = DAPRuntimeIdentifier("externalProcess")
    public static let kotlin = DAPRuntimeIdentifier("kotlin")
}

// MARK: - Manifest Model

public struct DAPAdapterManifest: Codable, Sendable {
    public let identifier: String
    public let displayName: String
    public let version: String
    public let runtime: DAPRuntimeIdentifier
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]
    public let languages: [String]
    public let capabilities: [DAPAdapterCapability]
    public let configurationFields: [DAPAdapterConfigurationField]
    public let supportsConditionalBreakpoints: Bool
    public let supportsWatchExpressions: Bool
    public let supportsPersistence: Bool
}

// MARK: - Schema Validator

public struct DAPConfigurationSchema: Sendable {
    public let requiredKeys: Set<String> = [
        "identifier", "displayName", "version", "runtime",
        "executable", "languages",
    ]

    /// Throws if required keys are missing or known invariants fail.
    public func validate(raw manifest: [String: Any]) throws {
        let missingKeys = requiredKeys.subtracting(manifest.keys)
        guard missingKeys.isEmpty else {
            throw DAPError.configurationInvalid(
                "Manifest is missing keys: \(missingKeys.sorted().joined(separator: ", "))"
            )
        }

        if let languages = manifest["languages"] as? [String], languages.isEmpty
        {
            throw DAPError.configurationInvalid(
                "Manifest must declare at least one language."
            )
        }

        if let executable = manifest["executable"] as? String,
            executable.isEmpty
        {
            throw DAPError.configurationInvalid(
                "Executable path cannot be empty."
            )
        }
    }
}

// MARK: - DAPConfigurationManager

public final class DAPConfigurationManager: @unchecked Sendable {
    private let logger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "DAPConfigurationManager"
    )
    private let schema = DAPConfigurationSchema()
    private let manifestsDirectory: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(
        label: "com.valkarystudio.debugger.config",
        qos: .userInitiated
    )
    private var observationSource: DispatchSourceFileSystemObject?

    public init(manifestsDirectory: URL) {
        self.manifestsDirectory = manifestsDirectory
    }

    /// Loads all adapter manifests from the configured directory (supports JSON and plist).
    /// Throws if any manifest fails schema or decoding.
    public func loadManifests() throws -> [DAPAdapterManifest] {
        let urls = try fileManager.contentsOfDirectory(
            at: manifestsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls.flatMap(loadManifest(at:))
    }

    /// Loads a manifest file (JSON/plist), validates, and decodes all entries.
    private func loadManifest(at url: URL) throws -> [DAPAdapterManifest] {
        let data = try Data(contentsOf: url)
        let raw: Any
        switch url.pathExtension.lowercased() {
        case "json":
            raw = try JSONSerialization.jsonObject(with: data)
        default:
            raw = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        }
        guard let array = raw as? [[String: Any]] else {
            throw DAPError.configurationInvalid(
                "Manifest must be an array of dictionaries. (\(url.lastPathComponent))"
            )
        }
        return try array.map { dict in
            try schema.validate(raw: dict)
            let manifestData = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(
                DAPAdapterManifest.self,
                from: manifestData
            )
        }
    }

    /// Watches the manifest directory and calls handler on any change (e.g., save, move, delete).
    public func watchForChanges(
        _ handler: @escaping @Sendable ([DAPAdapterManifest]) -> Void
    ) {
        queue.async { [self] in
            let fd = open(self.manifestsDirectory.path, O_EVTONLY)
            guard fd != -1 else {
                self.logger.error(
                    "Failed to open manifests directory for watching: \(self.manifestsDirectory.path)"
                )
                return
            }
            self.observationSource?.cancel()
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [
                    .write, .delete, .extend, .attrib, .link, .rename, .revoke,
                ],
                queue: self.queue
            )
            src.setEventHandler { [weak self] in
                guard let self else { return }
                do {
                    let manifests = try self.loadManifests()
                    handler(manifests)
                } catch {
                    self.logger.error(
                        "Failed to reload DAP adapter manifests: \(error.localizedDescription)"
                    )
                }
            }
            src.setCancelHandler { close(fd) }
            self.observationSource = src
            src.resume()
        }
    }
}
