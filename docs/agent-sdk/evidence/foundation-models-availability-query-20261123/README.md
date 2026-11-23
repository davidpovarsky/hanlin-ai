# Opt-in FoundationModels availability diagnostic

This adds one CLI option to the existing installed-interface inspector:

```sh
python3 Scripts/CI/inspect_foundation_models_interface.py \
  --output build/foundation-models-interface \
  --query-availability
```

Without `--query-availability`, the inspector remains declaration-only and records availability `NOT_QUERIED`. The new option is intended for the next necessary original Apple run. No separate Apple job or simulator was dispatched for this change.

## What is measured

The opt-in query compiles a small program against the installed official **macOS SDK** and executes it on the **macOS runner host**. It reads only `SystemLanguageModel.default.availability`, using the same public switch as the existing Hanlin provider. It does not create a LanguageModelSession, generate a response, call a tool, supply a prompt, query credentials, request permissions, download a model, or select a cloud provider. The existing declaration excerpt still comes from the installed iPhone Simulator SDK; the two execution/SDK contexts are named separately in the receipts.

The query records the actual Xcode, macOS SDK, Swift compiler, architecture and observed OS version; source and ephemeral executable SHA256; exact argv for each command; retained stdout/stderr bytes and hashes; exit status; duration; timeout/output-limit termination. Metadata commands have 10-second limits, compilation 60 seconds and query execution 10 seconds. Each command retains at most 64KiB per output stream and stops its own process group if a limit is exceeded. Commands that close output pipes before terminating remain subject to the deadline.

Compiler module caches and the temporary executable are kept in a query-owned temporary directory and removed afterward. They are not included in the uploaded artifact. The source, logs, executable identity and receipt remain under `availability-query/` inside the requested output directory. The parent inspector receipt refers to that receipt and projects only its observed availability and diagnostic status.

A successful diagnostic (`status: PASS`) means the availability property was read and its output admitted. An unavailable reason remains the actual availability value. **It is not model-generation or native-tool acceptance:** `modelExecution` and `toolExecution` remain `NOT_RUN`, and `toolCapability` remains `NOT_QUERIED`. Failure or timeout cannot become an available observation. Non-macOS execution is `BLOCKED` before compiling or running the diagnostic.

## Verification performed on Oracle

- Three portable Python controls PASS, 0.529 seconds. They verify the default opt-in boundary, actual subprocess output/closed-pipe timeout limits, and fixture receipt handling for unavailable, invalid and compiler-failure outputs. Fixture outputs are explicitly process-control inputs; no Apple model was simulated or executed.
- Embedded Swift source passed Swift frontend syntax parsing only on Linux. This is not an Apple SDK typecheck or runtime result.
- Python syntax and Git diff checks PASS.
- Actual macOS compilation and availability query: **NOT_RUN**, pending the next necessary original Apple job.
- SDK/native production sources, capabilities, Host schemas and workflows: unchanged.

The receipt binds the inspector, controls, embedded Swift source and verification log hashes. The necessary native adapter dependencies remain in the separate source-bound review: installed exact tool/schema declarations, original engine handoff and continuation proof, and eligible native model execution. This diagnostic resolves only the previously unqueried availability state when it actually runs.

## API sources

- [Existing original provider](https://github.com/davidpovarsky/hanlin-ai/blob/8429dbb6cb66e266504b8d055586829ba7aa61f7/Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleOnDeviceProvider.swift)
- [Apple availability property](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.property)
- [Apple availability enum](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum)
