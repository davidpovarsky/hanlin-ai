# Embedded MCP runtime

This downstream-only layer runs trusted JavaScript MCP servers locally inside Hanlin's iOS sandbox. Node.js Mobile is launched once on a dedicated native thread. The loopback host listens on an ephemeral `127.0.0.1` port protected by a random bearer token. Each active MCP server runs in its own `worker_threads` Worker with piped stdin, stdout, and stderr.

Server packages are never app resources. They are selected and installed after app installation into `Application Support/HanlinMCP/servers/<UUID>` through Pacote and Arborist APIs. Lifecycle scripts, native addons, external executables, global installs, shell execution, and package-manager CLIs are rejected.

Install preview exposes every supported package entry point when a package has multiple bins. Update and reinstall use a staging directory plus an atomic server-directory swap; the prior package remains as a temporary backup until the replacement completes MCP initialization and `tools/list`, and is restored automatically if that probe fails. The server detail screen can also start, stop, restart, refresh, and inspect the dynamically discovered tool catalog.

Host dependency versions were chosen as the newest releases observed on 2026-07-20 whose declared `engines.node` accepts 18.20.4: Arborist 8.0.5, Pacote 20.0.1, Semver 7.8.5, and SSRI 12.0.0. The lock contains 159 package records; all engine ranges were checked against 18.20.4.

## Build preparation

Run `bash Scripts/MCP/bootstrap-node-mobile.sh`. The script verifies the official Node.js Mobile archive and creates both the excluded `Vendor/NodeMobile/NodeMobile.xcframework` and the bundled host-only `AI_HLY/MCPHostResources.zip`.

## Upstream touchpoints

| Upstream file | Exact modification | Why unavoidable |
| --- | --- | --- |
| `AI_HLY/SettingsView.swift` | One navigation link in Tools | Opens the separate MCP settings UI |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | One separate MCP selector button beside the existing tool button | Provides per-chat server selection without replacing native tools |
| `AI_HLY/ChatView.swift` | Creates one immutable request scope and passes it with the request | Prevents global mutable current-chat state |
| `AI_HLY/Services/ChatServices/APIManager.swift` | Threads the scope, obtains schemas/presentation through `AssistantToolBridge`, and uses its native-first execution fallback | Connects dynamic tools at the existing narrow tool-call points |
| `AI_HLY/AI_HLY.swift` | Small scene lifecycle forwarding hook | Reconciles auto-start workers after foregrounding |
| `AI_HLY.xcodeproj/project.pbxproj` | Exact SPM products, NodeMobile link/embed, and Host source exclusion | Required compiler/linker/resource wiring |
| `AI-HLY-Info.plist` | Allows loopback-only local networking | Required for the authenticated private HTTP control plane |
| `.github/workflows/build-ios26-unsigned-ipa.yml` | Runs the deterministic bootstrap before Xcode inspection/build | Restores excluded binary and host bundle on the clean macOS runner |
