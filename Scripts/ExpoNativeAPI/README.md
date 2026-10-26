# Scripts/ExpoNativeAPI — Tooling & Verification

This directory contains deterministic build, codegen, preflight, and verification tooling for the NativeScript Native API JSI & Fabric integration in Hanlin Expo MiniApps.

## Scripts Overview

- `prepare-ios-dependencies.mjs`: Downloads checksummed npm tarballs (`@nativescript/react-native@9.1.2`, `react-native-worklets@0.13.1`), stages sources and native assets (`Libffi.xcframework`, metadata `.nsmd`), injects the native authorization gate, and triggers codegen.
- `generate-codegen.mjs`: Executes `@react-native/codegen` on `NativeScriptNativeApiSpec` and `rnworklets` specifications with schema hash verification.
- `verify-nsmd.mjs`: Inspects `metadata/*.nsmd` files, verifies magic `NSMD` headers and sha256 checksums.
- `verify-artifacts.mjs`: Audits `Packages/HanlinExpoNativeAPI/Artifacts` to ensure required binaries are staged and no duplicate `React` or `hermes` frameworks exist.
- `preflight.mjs`: Comprehensive verification of package versions, Babel configs, native SwiftPM structures, and JS facades.
- `build-probes.mjs`: Deterministic bundling of test `.hanlinExpo` ZIP packages (`ExpoNativeAPIProbeA`, `ExpoNativeAPIProbeB`, `ExpoNativeAPIProbeMissingGrant`, `ExpoNativeAPIProbeIncompatible`).
- `build-nativeapi-xcframework.sh`: Shell build harness for reproducible native artifact assembly.
