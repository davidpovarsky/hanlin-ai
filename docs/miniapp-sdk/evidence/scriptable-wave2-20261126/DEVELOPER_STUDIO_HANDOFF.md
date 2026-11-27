# Standalone MiniApps Developer Studio — source handoff

Date: 2026-11-26. Parent base: a78f50d77d69d5bf1d9c95c8588bb24a1069b33a.
Asana scope: 10 (1220917894278244), shared authoring support in 11.
This is a source and portable-test checkpoint. It is not Apple UI or iCloud acceptance.

## Implementation

Only the standalone MiniApps app supplies the optional Developer Studio toolbar action. The shared catalog retains its default behavior for other hosts. Studio uses the existing NodeRuntimeService, original TypeScript compiler, canonical miniapp-authoring SDK resolver, MiniAppAuthoringService validate/build, source package storage and original package import flow. It does not introduce a second compiler, a language-server protocol, a new script runtime, or the frozen Scripting-JSC/ScriptUI path.

The new editor operation overlays an unsaved UTF-16 buffer on the real TypeScript LanguageService and returns completions, selected declaration documentation, parameter help, semantic/syntactic diagnostics and the engine's official documentation URL. Paths are resolved within the project's existing canonical boundary. An editor cannot request an out-of-project symlink or cursor outside its buffer. Snippet placeholders are not inserted into the plain text editor.

The standalone UI includes native text editing/find, cursor-positioned completion suggestions, inline parameter/documentation help, diagnostics, installed-font selection, font sizes and system/light/dark themes. Source save/build/install uses the existing authoring and import services. The gallery reads actual examples from the SDK manifest and copies an independent editable project; the current manifest has four original Expo/NativeScript projects. No claim of a newly executed sample or an additional ScriptWidget gallery example is made here.

On-device folders use the existing runtime workspace. iCloud folders use the MiniApps app's already-declared iCloud.com.itorah.chavrusachat entitlement and Documents/MiniAppsStudio. Folder rename/move, nested folders, SF Symbol/color metadata, and Files folder import are implemented. File reads, writes, moves and import-copy coordinate with NSFileCoordinator on Apple platforms. Atomic replacement with Foundation options [] retains source file metadata, including existing Finder/Files labels, rather than re-creating custom Files tag colors. Hidden links are rejected on copy and folder metadata access. Existing destinations are never silently replaced.

Before each save, the original bytes must still match the file on disk. A second writer causes a visible conflict with Reload or Save a copy. Each window owns a persistent draft journal in existing app storage, so navigating away or a failed cloud save retains the user's text for recovery. The editor does not claim automatic cloud conflict resolution.

Live logs refresh off the main actor and read at most 512 KiB from the chosen log file. Search covers that visible recent section, which is explicitly labeled; Share exports the complete original file. This prevents an old multi-gigabyte log from being repeatedly loaded into the editor.

## Executed verification

Exact-source gate: Sentinel job job_d5a4ff974675, Oracle Swift 6.4.3 aarch64 Linux, 2026-11-26 12:51:02–12:51:13 UTC.

- Original TypeScript 5.9.3 editor tests: 4 PASS. Completion/JSDoc, active argument and Hebrew/emoji UTF-16 cursor handling, unsaved strict diagnostics without source rewriting, and cursor/path/symlink rejection.
- Exact Foundation workspace implementation: 4 Swift Testing tests PASS. Competing writers retain both versions; nested move retains source and appearance; new-file collision, traversal and symbolic links are rejected; independent example edits preserve the original; hidden-link import is rejected.
- Swift frontend parse: 8 changed/new Swift source files PASS.
- Node syntax check: original miniapp-authoring.mjs PASS.
- git diff --check: PASS before commit.

The portable test module copies the exact workspace source and tests, with no mock compiler or substitute Foundation implementation. It does not compile UIKit, SwiftUI, NSFileCoordinator, the application or an Apple extension. The TypeScript tests exercise the original installed compiler with their own project source; they do not substitute ambient SDK export declarations or certify every SDK export.

Original compiler path used without installing or copying a dependency:
 /mnt/development/projects/worktrees/hanlin-miniapps-sdk-recovery-20261125/Scripts/NativeScript/node_modules/typescript/lib/typescript.js

## Native acceptance handoff

Root owns native scheduling. No duplicate PR19 native suite has been launched by this lane.

1. Build HanlinMiniApps at the exact integrated source, including the four new app Swift files. This is the first Apple typecheck for this UI and the Darwin file-coordination branches.
2. Run HanlinMiniAppsTests/MiniAppsDeveloperWorkspaceTests on Apple Foundation. The Linux result does not certify Apple file-replacement/coordination behavior.
3. Launch the standalone MiniApps app. Tap accessibility ID miniapps-open-studio; expect miniapps-studio. Open On this device, then miniapps-studio-add > Gallery. Copy nativescript-hello-world and independently expo-hello-world, reopen the copied project, edit a typed member, verify completions/JSDoc/parameter help and deliberate type-error diagnostics. Check Hebrew/emoji selection, cursor popup placement, multiline editing, find, font/theme, keyboard and rotation on iPhone/iPad.
4. Use miniapps-studio-validate, then miniapps-studio-build-install. Complete the existing import flow and launch the installed edited project from the library. Verify the immutable SDK example is unchanged. Preserve actual run receipts; a build alone does not satisfy this scenario.
5. Rename/move a folder, reopen its source and icon/color. Create a nested file without replacing a destination. While two windows/devices edit the same source, confirm the second save presents a conflict, Save a copy preserves both, and reopening Recovered drafts retains an unsaved/conflicting draft.
6. With a signed-in iCloud-enabled device and the current entitlement, perform download, edit, rename and second-device conflict scenarios. This source checkpoint cannot certify iCloud propagation or physical-device behavior.
7. Open Live logs, select a file, search a known line, refresh after a real runtime event and export its complete file.

## Reference verification

- Original TypeScript language service API: https://github.com/microsoft/typescript/wiki/using-the-language-service-api
- Foundation metadata-preserving replacement: https://developer.apple.com/documentation/foundation/filemanager/replaceitemat%28_%3Awithitemat%3Abackupitemname%3Aoptions%3A%29?language=_2
- Scriptable 1.8 release comparison: https://apps.apple.com/bo/app/scriptable/id1405459188?platform=mac
- Scriptable FileManager limits (existing Files tags/colors; iCloud download APIs): https://scriptable.app/docs/reference/filemanager/

## Still open outside this checkpoint

Apple UI build/execution, real iCloud/File Provider conflicts, actual gallery example install/run, the separate Task 10 drawing audit/acceptance, and all physical-device/release gates. The available Mac SDK is iOS 27.0 (Xcode 27.0 27A266a); acceptance that specifically requires iOS 27.2 must not be reported as executed on 27.0.
