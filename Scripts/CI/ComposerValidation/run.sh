#!/bin/bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/composer-validation-evidence"
mkdir -p "$evidence"
actual_sha="$(git rev-parse HEAD)"
[[ "${COMPOSER_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Exact 40-character COMPOSER_EXPECTED_SHA is required' >&2; exit 2; }
[[ "$actual_sha" == "$COMPOSER_EXPECTED_SHA" ]] || { echo "Commit mismatch: $actual_sha" >&2; exit 2; }

selected_xcode="$(python3 -c 'import glob,re; paths=[p for p in glob.glob("/Applications/Xcode*.app") if "beta" not in p.lower()]; paths.sort(key=lambda p: tuple(map(int, re.findall(r"[0-9]+", p)))); print(paths[-1] if paths else "")')"
[[ -n "$selected_xcode" ]] || { echo 'No stable installed Xcode found' >&2; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version | tee "$evidence/xcode-version.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$evidence/ios-simulator-sdk-version.txt"

scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/composer-proof.XXXXXXXX")"
mkdir -p "$scratch/Sources/AI_Hanlin" "$scratch/Tests/AI_HanlinTests"
cp Scripts/CI/ComposerValidation/Package.swift "$scratch/Package.swift"
cmp Scripts/CI/ComposerValidation/Package.swift "$scratch/Package.swift"
sources=(
  AI_HLY/Downstream/ChatInput/HanlinMorphComposer.swift
  AI_HLY/Downstream/ChatInput/HanlinComposerPopupCoordinator.swift
  AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDockState.swift
)
test_source=AI_HLYTests/HanlinMorphComposerTests.swift
for file in "${sources[@]}" "$test_source"; do
  # The Git blob is compared against checkout bytes before copying, preventing
  # a dirty or line-ending-transformed file from being silently tested.
  git show "${actual_sha}:${file}" | cmp - "$file"
  case "$file" in
    AI_HLYTests/*) destination="$scratch/Tests/AI_HanlinTests/$(basename "$file")" ;;
    *) destination="$scratch/Sources/AI_Hanlin/$(basename "$file")" ;;
  esac
  cp "$file" "$destination"
  cmp "$file" "$destination"
  printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "$file" >> "$evidence/source-sha256.txt"
done
printf '%s\n' "$actual_sha" > "$evidence/source-commit.txt"
shasum -a 256 Scripts/CI/ComposerValidation/Package.swift Scripts/CI/ComposerValidation/run.sh Scripts/CI/ComposerValidation/verify_results.py > "$evidence/harness-sha256.txt"
printf '%s\n' 'Scope: Morph shell, popup coordinator and OrganizerDock state only.' \
  'NOT covered: ChatViewBottom, popup live consumers, production app UI and reference parity.' > "$evidence/scope.txt"

xcrun simctl list devices available -j > "$evidence/available-simulators.json"
device="$(jq -r '[.devices | to_entries[] | select(.key | contains("iOS-26")) | .value[] | select(.isAvailable and (.name | startswith("iPhone"))) | .udid] | first // empty' "$evidence/available-simulators.json")"
[[ -n "$device" ]] || { echo 'No available iOS 26 iPhone simulator in this isolated job' >&2; exit 2; }
printf '%s\n' "$device" > "$evidence/simulator-udid.txt"

set +e
(
  cd "$scratch"
  xcodebuild test -scheme AI_Hanlin \
    -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/Composer.xcresult" \
    -only-testing:AI_HanlinTests/HanlinMorphComposerTests
) 2>&1 | tee "$evidence/xcodebuild.log"
build_status=${PIPESTATUS[0]}
set -e
[[ "$build_status" == 0 ]] || exit "$build_status"
xcrun xcresulttool get test-results tests --path "$evidence/Composer.xcresult" --format json > "$evidence/tests.json"
python3 Scripts/CI/ComposerValidation/verify_results.py "$evidence/tests.json" | tee "$evidence/verified-cases.txt"
