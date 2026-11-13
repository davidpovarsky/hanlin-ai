# Prepared package version validation

[נועם | DEV] [MAIN_SESSION]. SDK-02 remains open.

The existing analyzer accepted malformed/future Core versions through a `9.1`
prefix, arbitrary Expo `58.*`, wildcard/latest declarations, malformed bridge
suffixes and non-string bridge requirements. These are import compatibility
checks, not npm dependency resolution. They now use the existing
HanlinPackageVersion parser and reject ambiguous or unavailable versions.

Prepared Core/Expo metadata requires a released three-component semantic version
in the installed major, no newer than Core9.1.0 / Expo runtime contract58.0.3.
The historical single ^/~ /=/v prefix remains a minimum-version shorthand.
Native widget exact runtime/plugin pins remain unchanged. Supplied dependency
maps must contain version strings; malformed maps and values produce findings
with their actual package.json path. Ordinary Scripting validation is unchanged.

Generated bridge3.0.0, workspace npm @hanlin/expo-ui1.0.0 and tooling npm
Expo58.0.0 are distinct version domains. The analyzer's existing plugin contract
is retained; no lockfile, runtime engine or generated bridge is rebuilt.

Compatibility findings gain an optional machine-readable code. Old findings
decode with nil, preserving their existing messages. New codes:

- MINIAPP_CORE_VERSION_MISMATCH
- MINIAPP_EXPO_VERSION_MISMATCH
- MINIAPP_BRIDGE_VERSION_INVALID
- MINIAPP_BRIDGE_VERSION_MISMATCH
- MINIAPP_DEPENDENCY_VERSION_INVALID

Four new analyzer methods cover27 runtime/bridge scenarios,4 malformed dependency
cases and legacy DTO decoding. Only exact helper extraction has been typechecked
locally with Swift6; this is not full analyzer execution. The affected native
HanlinScriptAnalyzerTests suite must execute on the existing focused package
workflow. Complete engine schemas, Host version/features, CLI remediation,
plugin/archive negatives and physical Host gates remain separate obligations.

Native execution evidence at0d9b67ec: run43328396255 executed14/14 analyzer
cases in0.163s, Xcode27.2/27B52 Swift6.4.2 arm64macOS27.0 (job2m54s).
Downloaded artifact13994196293, GitHub SHA256
79b3625dfdc6d9c55750fc86a84579e199e82b7661682817cd6c0b227df39523.
This proves import analyzer behavior, not direct Runtime session validation or
the complete SDK-02 schema/Host/device contract.

## Expo inspected entry versus launched entry

The Expo import Analyzer previously checked the declared script.json entry but
did not compare it with package.json main. The direct session then appended main
to the app root without rejecting parent traversal, absolute paths, malformed
types or symlinked entry components. Import could inspect one source while
launch loaded another.

Foreground Expo imports now require main to resolve to the exact inspected
entry. Missing main keeps the existing bundle.js default. A non-string main,
empty/absolute/parent/dot/backslash/URL path, missing file or mismatch yields
MINIAPP_ENTRYPOINT_INVALID at package.json. Widget-only handling is unchanged.
Direct Expo session construction rejects non-string and escaping paths, symlinked
package.json or any entry component, directories and missing files before
creating React/Hermes. Real regular files and nested relative main remain valid.

One new analyzer method covers8 malformed/mismatching values and the existing
implicit default. Three native constructor methods cover10 malformed values,
symlinked metadata/file/intermediate directory, missing/directory entry, and
positive default/nested files. Source parse and focused router regression passed;
actual affected analyzer and native constructor execution are still required.
This does not close the separate direct-session version-validator drift.
