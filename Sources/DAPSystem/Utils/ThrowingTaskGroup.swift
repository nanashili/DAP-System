//
//  ThrowingTaskGroup.swift
//  DAPSystem
//
//  Created by Tihan-Nico Paxton on 2025/09/22.
//

import Foundation

extension ThrowingTaskGroup where ChildTaskResult == Void {
    /// Adds tasks for each file that needs updating. Skips adding tasks when there are no files.
    mutating func addTaskUnlessEmpty(
        grouped: [URL: [DAPConditionalBreakpoint]],
        files: Set<URL>,
        _ action: @escaping (URL, [DAPConditionalBreakpoint]) async throws -> Void
    ) {
        guard !files.isEmpty else { return }
        for file in files {
            let bps = grouped[file] ?? []  // empty → clears breakpoints in that file
            addTask { try await action(file, bps) }
        }
    }
}
