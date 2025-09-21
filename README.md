# Valkary Studio Debugger Adapter Protocol System

**Valkary Studio** ships a fully modular [Debug Adapter Protocol (DAP)](https://microsoft.github.io/debug-adapter-protocol/) stack, isolating language-specific adapters behind a shared Swift runtime, manifest-driven configuration, and a clean UI coordination layer.  
Distributed as a Swift Package (`DAPFeature`), it’s plug-and-play for editors, custom IDEs, and CLI tools.

This guide covers:
- Installation and requirements
- Core architecture
- Runtime bootstrapping
- Session lifecycle management
- UI auto-generation
- Persistence and recovery
- Adding new adapters via manifests (no Swift code needed!)

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Architecture Overview](#architecture-overview)
- [Getting Started / Bootstrapping](#getting-started--bootstrapping)
- [Session Management](#session-management)
- [Configuration UI](#configuration-ui)
- [Persistence & Recovery](#persistence--recovery)
- [Adding a New Adapter](#adding-a-new-adapter)
- [Testing](#testing)
- [License](#license)

---

## Requirements

- **Swift 5.9+**, **macOS 14+**
- Just add `DAPFeature` as a dependency in your project.

```swift
// In Package.swift:
.products = [
    .library(name: "DAPSystem", targets: ["DAPSystem"])
]
```

---

## Installation

**Via Xcode (SPM UI):**
1. File ▸ Add Packages…
2. Enter repo URL:  
   `https://github.com/nanashili/DAP-System.git"`
3. Select **DAPSystem**.

**Via Package.swift:**
```swift
.package(url: "https://github.com/nanashili/DAP-System.git", from: "0.0.1")
```
Then add `DAPSystem` as a dependency.

---

## Architecture Overview

- **Protocol Core**  
  Message types (`DAPJSONValue`, `DAPMessage`), the broker, and event routing live at the foundation.
- **Adapter Isolation**  
  Concrete adapters (Kotlin, Python, Swift/LLDB, etc) implement the `DAPAdapter` protocol, and live in `Features/Debugger/DAP/Adapters/`. No adapter needs to know about others.
- **Declarative Manifests**  
  Adapters are declared with JSON manifests, hot-reloaded at runtime (see [Adding a New Adapter](#adding-a-new-adapter)).
- **Session Orchestration**  
  `DAPSession` handles handshake, breakpoints, run-control, and protocol events.
- **UI Coordination**  
  `DAPDebuggerCoordinator` bridges the registry and session store to your UI. `DAPConfigurationUIBuilder` transforms manifest metadata into native UI controls on the fly.
- **Persistence**  
  Sessions can be auto-resumed and recovered after crashes, thanks to `DAPSessionStore`.

---

## Getting Started / Bootstrapping

**Initialize the runtime and registry at launch:**

```swift
import DAPFeature

let manifestsURL = Bundle.main.url(forResource: "DebugAdapters", withExtension: nil, subdirectory: "App/Resources")!
let configurationManager = DAPConfigurationManager(manifestsDirectory: manifestsURL)
let sessionStore = DAPSessionStore(storageDirectory: applicationSupportURL.appendingPathComponent("Sessions"))
let registry = DAPAdapterRegistry(configurationManager: configurationManager, sessionStore: sessionStore)
registry.bootstrap()

let coordinator = DAPDebuggerCoordinator(registry: registry)
```

Adapters are loaded at startup and whenever a manifest changes on disk. No recompilation needed to add, update, or remove adapters.

**To update the UI on manifest changes:**
```swift
@MainActor
final class AdapterListViewModel: DAPAdapterRegistryDelegate {
    // ...
    func adapterRegistry(_ registry: DAPAdapterRegistry, didUpdateAvailableAdapters adapters: [DAPAdapterManifest]) {
        // Refresh UI
    }
}
```

---

## Session Management

Control debugger sessions from your UI using `DAPDebuggerCoordinator`.

```swift
@MainActor
func startSession(for manifest: DAPAdapterManifest, projectURL: URL) async {
    let config: [String: DAPJSONValue] = [
        "request": .string("launch"),
        "program": .string(projectURL.path),
        "stopOnEntry": .bool(false)
    ]
    await coordinator.startSession(with: manifest, configuration: config)
}
```

**Advanced event handling:**
```swift
let adapter = try registry.makeAdapter(for: manifest)
let session = try adapter.prepareSession(configuration: config)
session.onEvent = { event in
    // Handle stopped, output, etc.
}
try await adapter.startSession()
```

All DAP requests—breakpoints, stack frames, variables, memory, etc—are available as async methods on `DAPSession`.

---

## Configuration UI

Adapter manifests define configuration fields. `DAPConfigurationUIBuilder` autogenerates sections and controls:

```swift
let sections = DAPConfigurationUIBuilder().makeSections(for: manifest)
for section in sections {
    // Use section.title, section.fields for building your form UI.
}
```

Supports `.text`, `.secureText`, `.toggle`, `.picker(options:)`, and `.number`. Required/optional fields, defaults, descriptions, and options are all defined in the manifest.

---

## Persistence & Recovery

`DAPSessionStore` persists active sessions, allowing automatic recovery after app restart or crash:

- Load recoverable sessions from disk
- Filter by adapters that support persistence
- Expose sessions via `recoverableSessions`
- Resume or discard sessions with one call

Show a “Resume previous session?” banner in your UI—no extra backend code required.

---

## Adding a New Adapter

**No Swift code needed!**  
Just drop a JSON manifest in your debug adapters directory:

```json
[
  {
    "identifier": "com.example.adapters.rust",
    "displayName": "Rust GDB",
    "version": "0.1.0",
    "runtime": "externalProcess",
    "executable": "rust-gdb-debug-adapter",
    "arguments": ["--stdio"],
    "environment": {"RUST_LOG": "debug"},
    "languages": ["rust"],
    "capabilities": [
      { "name": "launch", "description": "Launch Rust binaries", "isRequired": true }
    ],
    "configurationFields": [
      { "key": "program", "title": "Executable", "type": "text", "description": "Path to the compiled binary" }
    ],
    "supportsConditionalBreakpoints": true,
    "supportsWatchExpressions": true,
    "supportsPersistence": false
  }
]
```

**That’s it.**  
The registry picks up new/updated manifests on the fly.

Want a fully custom adapter (native Swift, advanced runtime, etc)?  
Register a factory in code:
```swift
registry.registerFactory({ manifest, context in
    MyCustomAdapter(manifest: manifest, context: context)
}, forRuntimeString: "customRuntime")
```
Custom adapters can inherit from `BaseDAPAdapter` or `ExternalProcessDAPAdapter`.

---

## Testing

Run tests with SwiftPM:
```bash
swift test
```
Covers manifest loading, registry updates, session flows, UI generation, and persistence.

---

## License

See [LICENSE](LICENSE).

---

**Fast to embed. Easy to extend. Production-ready.**
