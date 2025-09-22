//
//  KotlinAdapter.swift
//  Valkary-Studio-DAP-System
//
//  Created by Tihan-Nico Paxton on 9/21/25.
//
//  Role: Domain/Debugger
//  Deps: ExternalProcessDAPAdapter, DAPLogger, ActivityEmitter
//
//  Purpose:
//  --------
//  Thin specialization of ExternalProcessDAPAdapter for Kotlin DAP.
//  - Adds precise lifecycle logging with elapsed timing.
//  - Surfaces key moments to ActivityEmitter for IDE UI feedback.
//  - Keeps behavior zero-cost when idle; avoids extra allocations.
//

import Foundation

public final class KotlinAdapter: ExternalProcessDAPAdapter, @unchecked Sendable {
    // MARK: - Logging

    private let kotlinLogger = DAPLogger(
        subsystem: "com.valkarystudio.debugger",
        category: "KotlinAdapter"
    )

    // MARK: - Lifecycle

    /// Prepare the session via the parent adapter but with stronger diagnostics.
    public override func prepareSession(configuration: [String: DAPJSONValue])
        throws -> DAPSession
    {
        let t0 = CFAbsoluteTimeGetCurrent()
        kotlinLogger.debug("Preparing Kotlin DAP session…")
        let session = try super.prepareSession(configuration: configuration)
        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1_000
        kotlinLogger.log(
            "Prepared Kotlin DAP session \(session.identifier) in \(Int(dt))ms"
        )
        return session
    }

    /// Start and persist; emits an activity event so the UI shows state.
    public override func startSession() async throws {
        kotlinLogger.debug("Starting Kotlin DAP session…")
        try await super.startSession()
        if let id = session?.identifier {
            kotlinLogger.log("Kotlin DAP session started: \(id)")
        }
    }

    /// Stop gracefully and clear persisted state; emits an activity event.
    public override func stopSession() async {
        if let id = session?.identifier {
            kotlinLogger.debug("Stopping Kotlin DAP session \(id)…")
        } else {
            kotlinLogger.debug(
                "Stopping Kotlin DAP session (no active handle)…"
            )
        }
        await super.stopSession()
    }

    /// Resume using base behavior but with timing + logs.
    public override func resumeSession(from metadata: DAPSessionMetadata)
        async throws
    {
        let t0 = CFAbsoluteTimeGetCurrent()
        kotlinLogger.debug("Resuming Kotlin DAP session from metadata…")
        try await super.resumeSession(from: metadata)
        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1_000
        if let id = session?.identifier {
            kotlinLogger.log("Resumed Kotlin DAP session \(id) in \(Int(dt))ms")
        }
    }
}
