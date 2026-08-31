#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="$1"
SIMULATOR_UDID="$2"
BUNDLE_ID="$3"
PACKAGE_E2E_STATUS="$4"

REPRO_ROOT="$LOG_DIR/script-app-node-restart-repro"
SCREENSHOTS="$REPRO_ROOT/screenshots"
REPRO_LOGS="$REPRO_ROOT/logs"
mkdir -p "$SCREENSHOTS" "$REPRO_LOGS"
DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
FIXTURE_SOURCE="AI_HLYTests/Fixtures/ScriptingFixtures.bundle/PhysicalIPad/smart-eating-normalized.zip"
FIXTURE_DESTINATION="$DATA_CONTAINER/Documents/smart-eating-normalized.zip"
mkdir -p "$DATA_CONTAINER/Documents"
cp "$FIXTURE_SOURCE" "$FIXTURE_DESTINATION"
shasum -a 256 "$FIXTURE_SOURCE" | awk '{print $1}' > "$REPRO_ROOT/exact-package-sha256.txt"
test "$(cat "$REPRO_ROOT/exact-package-sha256.txt")" = "c8ee66e4e5e6a06a884b2a1d7b552d51691cb824f245e4cca238bc44d1509d57"
printf '%s\n' "$GITHUB_SHA" > "$REPRO_ROOT/git-sha.txt"
cp "$LOG_DIR/simulator-model.txt" "$REPRO_ROOT/simulator-model.txt"
cp "$LOG_DIR/simulator-runtime.txt" "$REPRO_ROOT/simulator-runtime.txt"
cp "$LOG_DIR/01-environment.log" "$REPRO_ROOT/environment.log"
cat > "$REPRO_ROOT/03-system-file-picker-unavailable.txt" <<'EOF'
The system Files/File Provider picker is controlled by a separate process and cannot be seeded and selected deterministically on a clean GitHub-hosted Simulator. This host-process regression uses the exact ZIP copied into the app container and invokes the same production HanlinPackageCenter importer. The visible Apps lifecycle and the genuine terminate/relaunch boundary remain real; picker/security-scope behavior is covered separately by the exact-archive production test.
EOF

checkpoint_path() {
  printf '%s/Library/Application Support/Hanlin/ScriptAppNodeRestartRepro/%s' "$DATA_CONTAINER" "$1"
}

wait_checkpoint() {
  checkpoint="$1"
  pid="$2"
  ready="$(checkpoint_path "$checkpoint.ready")"
  deadline=$((SECONDS + 300))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$ready" ]; then return 0; fi
    if ! xcrun simctl spawn "$SIMULATOR_UDID" launchctl print "pid/$pid" >/dev/null 2>&1; then
      echo "Host process $pid exited before checkpoint $checkpoint" >&2
      return 1
    fi
    sleep 1
  done
  echo "Timed out waiting for checkpoint $checkpoint" >&2
  return 1
}

capture_checkpoint() {
  checkpoint="$1"
  screenshot="$2"
  json="$(checkpoint_path "$checkpoint.json")"
  cp "$json" "$REPRO_LOGS/$checkpoint.json"
  xcrun simctl io "$SIMULATOR_UDID" screenshot "$SCREENSHOTS/$screenshot.png"
  touch "$(checkpoint_path "continue-$checkpoint")"
}

capture_filesystem_state() {
  suffix="$1"
  PLATFORM_ROOT="$DATA_CONTAINER/Library/Application Support/Hanlin/ScriptingPlatform"
  STORE_ROOT="$PLATFORM_ROOT/Installed"
  REGISTRY="$STORE_ROOT/registry/catalog.json"
  if [ -f "$REGISTRY" ]; then
    cp "$REGISTRY" "$REPRO_ROOT/registry-$suffix.json"
  else
    printf '%s\n' '{}' > "$REPRO_ROOT/registry-$suffix.json"
  fi
  if [ -d "$PLATFORM_ROOT" ]; then
    find "$PLATFORM_ROOT" -print | sort > "$REPRO_ROOT/filesystem-$suffix.txt"
  else
    printf '%s\n' '<missing>' > "$REPRO_ROOT/filesystem-$suffix.txt"
  fi
  python3 - "$REGISTRY" "$PLATFORM_ROOT" "$FIXTURE_DESTINATION" "$REPRO_ROOT/artifact-paths-$suffix.json" <<'PY'
import json
import os
import sys

registry_path, platform_root, source_url, output = sys.argv[1:]
registry = {}
if os.path.isfile(registry_path):
    with open(registry_path, encoding="utf-8") as stream:
        registry = json.load(stream)
entries = registry.get("packages", {})
packages = []
for key, entry in sorted(entries.items()):
    record = entry.get("record", {})
    generation = record.get("activeGeneration")
    package_root = os.path.join(platform_root, "Installed", "packages", key)
    artifact_root = os.path.join(package_root, "generations", str(generation))
    manifest = os.path.join(artifact_root, "artifact-manifest.json")
    generation_root = os.path.join(package_root, "generations")
    packages.append({
        "packageID": key,
        "runtimeKinds": sorted(item.get("runtimeProfile", "") for item in entry.get("entrypoints", [])),
        "activeGeneration": generation,
        "availableGenerations": sorted(os.listdir(generation_root)) if os.path.isdir(generation_root) else [],
        "packageRoot": package_root,
        "artifactRoot": artifact_root,
        "artifactManifestURL": manifest,
        "artifactManifestExists": os.path.isfile(manifest),
        "artifactManifestParentExists": os.path.isdir(artifact_root),
        "entrypoints": sorted(item.get("sourcePath", "") for item in entry.get("entrypoints", [])),
    })
payload = {
    "registryPath": registry_path,
    "registryExists": os.path.isfile(registry_path),
    "platformRoot": platform_root,
    "standardizedPlatformRoot": os.path.normpath(platform_root),
    "symlinkResolvedPlatformRoot": os.path.realpath(platform_root),
    "securityScopedSourceURL": source_url,
    "securityScopedSourceExists": os.path.isfile(source_url),
    "importStagingEntries": sorted(os.listdir(os.path.join(platform_root, "ImportStaging"))) if os.path.isdir(os.path.join(platform_root, "ImportStaging")) else [],
    "storeStagingEntries": sorted(os.listdir(os.path.join(platform_root, "Installed", "staging"))) if os.path.isdir(os.path.join(platform_root, "Installed", "staging")) else [],
    "packages": packages,
}
with open(output, "w", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True, ensure_ascii=False)
    stream.write("\n")
PY
}

set +e
SIMCTL_CHILD_HANLIN_SCRIPT_RESTART_REPRO_PHASE=install \
SIMCTL_CHILD_HANLIN_SCRIPT_RESTART_REPRO_FIXTURE="$FIXTURE_DESTINATION" \
  xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" 2>&1 \
  | tee "$REPRO_LOGS/install-process-launch.txt"
install_launch_status="${PIPESTATUS[0]}"
set -e
test "$install_launch_status" -eq 0
INSTALL_PID="$(awk -F ': ' -v bundle="$BUNDLE_ID" '$1 == bundle { print $2 }' "$REPRO_LOGS/install-process-launch.txt" | tail -1)"
test -n "$INSTALL_PID"
printf '%s\n' "$INSTALL_PID" > "$REPRO_ROOT/install-process-pid.txt"

wait_checkpoint 01-clean-apps-screen "$INSTALL_PID"
capture_checkpoint 01-clean-apps-screen 01-clean-apps-screen
wait_checkpoint 02-import-flow-open "$INSTALL_PID"
capture_checkpoint 02-import-flow-open 02-import-flow-open
wait_checkpoint 04-import-completed "$INSTALL_PID"
capture_checkpoint 04-import-completed 04-package-selected-or-import-completed
wait_checkpoint 05-imported-app-visible "$INSTALL_PID"
capture_checkpoint 05-imported-app-visible 05-imported-app-visible
capture_filesystem_state after-install
wait_checkpoint 06-first-launch-result "$INSTALL_PID"
capture_checkpoint 06-first-launch-result 06-first-launch-restart-required
capture_filesystem_state after-first-launch
wait_checkpoint 07-before-process-termination "$INSTALL_PID"
cp "$(checkpoint_path 07-before-process-termination.json)" "$REPRO_LOGS/07-before-process-termination.json"
xcrun simctl io "$SIMULATOR_UDID" screenshot "$SCREENSHOTS/07-after-restart-required-dismissed.png"
capture_filesystem_state before-restart
touch "$(checkpoint_path continue-07-before-process-termination)"
xcrun simctl spawn "$SIMULATOR_UDID" log show --style compact --last 10m \
  --predicate "processID == $INSTALL_PID" > "$REPRO_LOGS/install-process.log" 2>&1 || true
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID"

set +e
SIMCTL_CHILD_HANLIN_SCRIPT_RESTART_REPRO_PHASE=restore \
  xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" 2>&1 \
  | tee "$REPRO_LOGS/restore-process-launch.txt"
restore_launch_status="${PIPESTATUS[0]}"
set -e
test "$restore_launch_status" -eq 0
RESTORE_PID="$(awk -F ': ' -v bundle="$BUNDLE_ID" '$1 == bundle { print $2 }' "$REPRO_LOGS/restore-process-launch.txt" | tail -1)"
test -n "$RESTORE_PID"
test "$RESTORE_PID" != "$INSTALL_PID"
printf '%s\n' "$RESTORE_PID" > "$REPRO_ROOT/restore-process-pid.txt"
wait_checkpoint 08-after-process-relaunch-apps-screen "$RESTORE_PID"
cp "$(checkpoint_path 08-after-process-relaunch-apps-screen.json)" "$REPRO_LOGS/08-after-process-relaunch-apps-screen.json"
xcrun simctl io "$SIMULATOR_UDID" screenshot "$SCREENSHOTS/08-after-process-relaunch-apps-screen.png"
capture_filesystem_state after-restart
touch "$(checkpoint_path continue-08-after-process-relaunch-apps-screen)"
wait_checkpoint 09-second-launch-result "$RESTORE_PID"
capture_checkpoint 09-second-launch-result 09-second-launch-result
capture_filesystem_state after-second-launch
xcrun simctl spawn "$SIMULATOR_UDID" log show --style compact --last 10m \
  --predicate "processID == $RESTORE_PID" > "$REPRO_LOGS/restore-process.log" 2>&1 || true
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID"

python3 - "$REPRO_LOGS/09-second-launch-result.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("activity") != "idle":
    raise SystemExit(f"Second launch failed after a real host-process restart: {payload.get('activity')}")
if not payload.get("packages"):
    raise SystemExit("Persisted Script App registry was empty after host-process restart")
PY
test "$PACKAGE_E2E_STATUS" -eq 0
