//
//  DAPConfigurationFieldViewModel.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Purpose:
//  --------
//  - Maps DAPAdapterManifest configuration fields into structured UI sections.
//  - Normalizes field/option/required-ness into ergonomic control types for use in SwiftUI forms.
//

import Foundation

public struct DAPConfigurationFieldViewModel: Sendable, Equatable {
    public enum ControlType: Sendable, Equatable {
        case text
        case secureText
        case toggle
        case picker(options: [String])
        case number
    }

    public let key: String
    public let title: String
    public let controlType: ControlType
    public let defaultValue: DAPJSONValue?
    public let description: String?
    public let isRequired: Bool
}

public struct DAPConfigurationSection: Sendable, Equatable {
    public let title: String
    public let fields: [DAPConfigurationFieldViewModel]
}

/// Transforms a DAP manifest into UI sections for configuration (required & optional).
public struct DAPConfigurationUIBuilder: Sendable {
    public init() {}

    /// Produces grouped UI sections based on required/optional status.
    public func makeSections(for manifest: DAPAdapterManifest)
        -> [DAPConfigurationSection]
    {
        guard !manifest.configurationFields.isEmpty else { return [] }

        let requiredFields = manifest.configurationFields.filter {
            $0.defaultValue == nil
        }
        let optionalFields = manifest.configurationFields.filter {
            $0.defaultValue != nil
        }

        // If all required or all optional, just one section
        if requiredFields.isEmpty || optionalFields.isEmpty {
            let fields = manifest.configurationFields.map { field in
                makeViewModel(
                    for: field,
                    isRequired: requiredFields.contains { $0.key == field.key }
                )
            }
            return [
                DAPConfigurationSection(
                    title: manifest.displayName,
                    fields: fields
                )
            ]
        }

        let requiredSection = DAPConfigurationSection(
            title: "\(manifest.displayName) (Required)",
            fields: requiredFields.map {
                makeViewModel(for: $0, isRequired: true)
            }
        )
        let optionalSection = DAPConfigurationSection(
            title: "\(manifest.displayName) (Optional)",
            fields: optionalFields.map {
                makeViewModel(for: $0, isRequired: false)
            }
        )

        return [requiredSection, optionalSection]
    }

    /// Converts a raw manifest field into a ViewModel for UI use.
    private func makeViewModel(
        for field: DAPAdapterConfigurationField,
        isRequired: Bool
    ) -> DAPConfigurationFieldViewModel {
        DAPConfigurationFieldViewModel(
            key: field.key,
            title: field.title,
            controlType: controlType(for: field),
            defaultValue: field.defaultValue,
            description: field.description,
            isRequired: isRequired
        )
    }

    /// Maps manifest field type into UI control type (SwiftUI-ergonomic).
    private func controlType(for field: DAPAdapterConfigurationField)
        -> DAPConfigurationFieldViewModel.ControlType
    {
        switch field.type {
        case .text: return .text
        case .password: return .secureText
        case .toggle: return .toggle
        case .selection: return .picker(options: field.options ?? [])
        case .number: return .number
        }
    }
}
