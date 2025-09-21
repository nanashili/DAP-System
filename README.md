# Debugger Adapter Protocol System
Valkary Studio ships a fully modular Debug Adapter Protocol (DAP) implementation that keeps language-specific adapters isolated while sharing a common runtime, configuration, and UI coordination layer. The package is distributed as a Swift Package Manager library (`DAPFeature`) so the debugger stack can be embedded in other editors or tooling.

This README describes how the system is organised, how to install and embed the package, and the steps required to add additional debug adapters through declarative manifests without touching any Swift code.

## Table of contents
- [Requirements](#requirements)
- [Installation](#installation)
- [Architecture overview](#architecture-overview)
- [Bootstrapping the debugger runtime](#bootstrapping-the-debugger-runtime)
- [Starting and managing sessions](#starting-and-managing-sessions)
- [Configuration UI generation](#configuration-ui-generation)
- [Session persistence and recovery](#session-persistence-and-recovery)
- [Adding a new debug adapter](#adding-a-new-debug-adapter)
- [Testing](#testing)
- [License](#license)

## Requirements

`DAPFeature` targets Swift 5.9 and macOS 13 or newer. The Swift Package manifest exposes a single public product so the module can be added to macOS applications, command-line tools, or other packages.

```swift
// Package.swift
.products = [
    .library(name: "DAPFeature", targets: ["DAPFeature"])
]
```

## Installation

### Swift Package Manager (Xcode)
1. Open your project in Xcode.
2. Navigate to **File ▸ Add Packages…**.
3. Enter the repository URL (e.g. `https://github.com/<your-org>/Valkary-Studio.git`).
4. Select **DAPFeature** and add it to the desired targets.

### Swift Package Manager (Package.swift)
Add the dependency to your package manifest:

```swift
.package(url: "https://github.com/<your-org>/Valkary-Studio.git", from: "1.0.0")
```

Then add `DAPFeature` to the target dependencies:

```swift
.target(
    name: "MyEditor",
    dependencies: [
        .product(name: "DAPFeature", package: "ValkaryStudio")
    ]
)
```

After resolving dependencies, import `DAPFeature` wherever you need to drive the debugger.

## Architecture overview

The package follows a feature-module architecture designed for hot-swappable adapters and declarative configuration:

- **Protocol core** — `DAPJSONValue`, `DAPMessage`, and `DAPMessageBroker` provide typed request/response handling, multiplexing, and event routing for the Debug Adapter Protocol.
- **Adapter isolation** — The `DAPAdapter` protocol and `BaseDAPAdapter` class enforce a uniform lifecycle (`prepareSession`, `startSession`, `stopSession`, `resumeSession`). Concrete adapters (Swift/LLDB, Node.js, Python, Kotlin, external processes) live under `Features/Debugger/DAP/Adapters/` and only depend on the shared infrastructure.
- **Declarative manifests** — `DAPConfigurationManager` loads JSON manifests, validates them, and watches the filesystem for changes so adapters can be added or updated at runtime without recompilation.
- **Session orchestration** — `DAPSession` manages the DAP handshake, breakpoint and exception synchronization, run-control commands, stack inspection, and event emission.
- **UI coordination** — `DAPDebuggerCoordinator` bridges the registry, session store, and UI, while `DAPConfigurationUIBuilder` turns manifest metadata into editor-friendly form controls.
- **Persistence** — `DAPSessionStore` records active sessions for recovery, enabling editors to resume compatible sessions after restarts.

## Bootstrapping the debugger runtime

Create the shared infrastructure at app launch. The example below loads the bundled manifests from `App/Resources/DebugAdapters/`, enables hot reloading, and prepares a coordinator for UI integration.

```swift
import DAPFeature

let manifestsURL = Bundle.main.url(forResource: "DebugAdapters", withExtension: nil, subdirectory: "App/Resources")!
let configurationManager = DAPConfigurationManager(manifestsDirectory: manifestsURL)
let sessionStore = DAPSessionStore(storageDirectory: applicationSupportURL.appendingPathComponent("Sessions"))
let registry = DAPAdapterRegistry(configurationManager: configurationManager, sessionStore: sessionStore)
registry.bootstrap() // Loads existing manifests and begins watching for changes.

let coordinator = DAPDebuggerCoordinator(registry: registry)
```

`bootstrap()` registers the built-in adapter factories (including `ExternalProcessDAPAdapter`, Swift/LLDB, Node.js, Python, and Kotlin shims), loads manifests, and starts watching the directory. When files change, the registry updates its manifest cache and notifies the delegate on the main queue.

To react to manifest changes in the UI, assign a delegate:

```swift
@MainActor
final class AdapterListViewModel: DAPAdapterRegistryDelegate {
    private let coordinator: DAPDebuggerCoordinator
    private let registry: DAPAdapterRegistry

    init(coordinator: DAPDebuggerCoordinator, registry: DAPAdapterRegistry) {
        self.coordinator = coordinator
        self.registry = registry
        registry.delegate = self
    }

    func adapterRegistry(
        _ registry: DAPAdapterRegistry,
        didUpdateAvailableAdapters adapters: [DAPAdapterManifest]
    ) {
        // Update published adapter list for the UI.
    }
}
```

## Starting and managing sessions

`DAPDebuggerCoordinator` centralises session lifecycle management. Use it to start, resume, and stop sessions from your UI layer.

```swift
@MainActor
func startSwiftSession(with manifest: DAPAdapterManifest, projectURL: URL) async {
    var configuration: [String: DAPJSONValue] = [
        "request": .string("launch"),
        "program": .string(projectURL.path),
        "stopOnEntry": .bool(false)
    ]

    await coordinator.startSession(with: manifest, configuration: configuration)
}
```

When a session starts successfully, the underlying adapter:

1. Creates a `DAPSession` bound to its transport (e.g. an external process).
2. Performs the DAP handshake (`initialize` → `configurationDone` → `launch`/`attach`).
3. Streams protocol events via `DAPSession.onEvent` (initialised, stopped, continued, terminated, output).
4. Synchronises breakpoints, exception filters, and watch expressions when capabilities are advertised.

To observe runtime events or drive advanced inspection APIs, obtain the adapter directly from the registry and retain the returned session reference before starting it:

```swift
let adapter = try registry.makeAdapter(for: manifest)
let session = try adapter.prepareSession(configuration: configuration)

session.onEvent = { event in
    switch event {
    case .stopped(let payload):
        // Refresh call stack, scopes, and variables.
    case .output(let message):
        // Append output to the console.
    default:
        break
    }
}

try await adapter.startSession()
```

Breakpoints, threads, stack frames, scopes, variables, completions, modules, memory reads/writes, and other advanced requests are exposed through asynchronous methods on `DAPSession`.

## Configuration UI generation

Manifests describe configuration fields using `DAPAdapterConfigurationField`. `DAPConfigurationUIBuilder` converts those definitions into sections that the editor can render without hard-coding controls.

```swift
let sections = DAPConfigurationUIBuilder().makeSections(for: manifest)
for section in sections {
    print(section.title)
    for field in section.fields {
        switch field.controlType {
        case .text: /* render standard text field */
        case .secureText: /* render password input */
        case .toggle: /* render checkbox/switch */
        case .picker(let options): /* render segmented control or menu */
        case .number: /* render numeric stepper */
        }
    }
}
```

Required and optional inputs are grouped automatically, and defaults, helper text, and option lists are preserved so forms can be pre-populated and documented inline.

## Session persistence and recovery

`DAPSessionStore` writes metadata for each active session to disk. The coordinator automatically:

- Loads persisted sessions on initialisation.
- Filters entries to manifests that opt into persistence (`supportsPersistence == true`).
- Exposes recoverable sessions via the `recoverableSessions` array.
- Provides APIs to resume (`resumePersistedSession`), discard (`discardPersistedSession`), or automatically clean up sessions when they end.

The host application can present the recovered metadata in its UI so users can resume long-running sessions after crashes or restarts.

## Adding a new debug adapter

Adapters are discovered declaratively from JSON manifests stored alongside the app (the repository ships examples under `App/Resources/DebugAdapters/`). Adding support for a new language requires three steps:

1. **Drop in a manifest.** Create a JSON file that matches the `DAPAdapterManifest` schema. At minimum you must provide `identifier`, `displayName`, `version`, `runtime`, `executable`, and `languages`.

    ```json
    [
      {
        "identifier": "com.example.adapters.rust",
        "displayName": "Rust GDB",
        "version": "0.1.0",
        "runtime": "externalProcess",
        "executable": "rust-gdb-debug-adapter",
        "arguments": ["--stdio"],
        "workingDirectory": null,
        "environment": {"RUST_LOG": "debug"},
        "languages": ["rust"],
        "capabilities": [
          { "name": "launch", "description": "Launch Rust binaries", "isRequired": true }
        ],
        "configurationFields": [
          {
            "key": "program",
            "title": "Executable",
            "type": "text",
            "description": "Path to the compiled binary"
          }
        ],
        "supportsConditionalBreakpoints": true,
        "supportsWatchExpressions": true,
        "supportsPersistence": false
      }
    ]
    ```

2. **Bundle the manifest.** Place the file in the manifests directory bundled with your app (or configure `DAPConfigurationManager` to watch a custom location). The registry will automatically pick it up on the next refresh.

3. **Provide a runtime factory (optional).** If the adapter can be launched with the existing `ExternalProcessDAPAdapter`, no additional code is required. For specialised runtimes, register a custom factory:

    ```swift
    registry.registerFactory({ manifest, context in
        MyCustomAdapter(manifest: manifest, context: context)
    }, forRuntimeString: "customRuntime")
    ```

    Custom adapters can inherit from `BaseDAPAdapter` or `ExternalProcessDAPAdapter` to reuse transport and session persistence logic.

Because manifests are watched at runtime, shipping a new adapter can be as simple as adding a JSON file to the manifests directory.

## Testing

Run the unit test suite with Swift Package Manager:

```bash
swift test
```

The tests exercise manifest loading and validation, adapter registry updates, session lifecycle flows, configuration UI generation, external process environment management, and persistence behaviors.

## License

This project is released under the terms of the [LICENSE](LICENSE) file in the repository.
