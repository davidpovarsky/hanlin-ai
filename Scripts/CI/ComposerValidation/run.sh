#!/bin/bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/composer-validation-evidence"
mkdir -p "$evidence"
actual_sha="$(git rev-parse HEAD)"
[[ "${COMPOSER_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Exact 40-character COMPOSER_EXPECTED_SHA is required' >&2; exit 2; }
[[ "$actual_sha" == "$COMPOSER_EXPECTED_SHA" ]] || { echo "Commit mismatch: $actual_sha" >&2; exit 2; }

selected_xcode="$(python3 -c 'import glob,re; paths=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; paths.sort(key=lambda p: tuple(map(int, re.findall(r"[0-9]+", p)))); print(paths[-1] if paths else "")')"
[[ -n "$selected_xcode" ]] || { echo 'No stable installed Xcode found' >&2; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version | tee "$evidence/xcode-version.txt"
xcrun swift --version | tee "$evidence/swift-version.txt"
sw_vers > "$evidence/host-version.txt"
sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
printf '%s\n' "$sdk_version" | tee "$evidence/ios-simulator-sdk-version.txt"
ios_major="${sdk_version%%.*}"
[[ "$ios_major" == 27 ]] || { echo 'Actual iOS Simulator SDK 27 required' >&2; exit 2; }

scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/composer-proof.XXXXXXXX")"
package_dir="$scratch/ComposerValidation"
python3 Scripts/CI/ComposerValidation/prepare_capability_proof.py \
  --repo "$root" --source-sha "$actual_sha" --output "$package_dir" --with-editor-tests \
  | tee "$evidence/preparation.json"
cp "$package_dir/proof-inputs.json" "$evidence/proof-inputs.json"
cp "$package_dir/Package.swift" "$evidence/Harness-Package.swift"
python3 - "$root" "$evidence/proof-inputs.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
inputs = json.loads(pathlib.Path(sys.argv[2]).read_text())
for path, digest in inputs['input_sha256'].items():
    if hashlib.sha256((root / path).read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Git/checkout input mismatch: {path}')
PY
tar -C "$package_dir" -cf "$evidence/source-inputs.tar" Package.swift Sources Tests proof-inputs.json
printf '%s\n' "$actual_sha" > "$evidence/source-commit.txt"
shasum -a 256 Scripts/CI/ComposerValidation/Package.swift Scripts/CI/ComposerValidation/run.sh Scripts/CI/ComposerValidation/verify_results.py Scripts/CI/ComposerValidation/prepare_capability_proof.py > "$evidence/harness-sha256.txt"
printf '%s\n' 'Scope: eight whole production component files; every declared Morph and UIKit editor case from the two complete owner test files, with exact identities in proof-inputs.json.' \
  'NOT covered: parity/session/manual dock resize, ChatViewBottom, popup live consumers, production app UI, physical device or reference parity.' > "$evidence/scope.txt"

xcrun simctl list devices available -j > "$evidence/available-simulators.json"
device="$(jq -r --arg runtime "iOS-$ios_major-" '[.devices | to_entries[] | select(.key | contains($runtime)) | .value[] | select(.isAvailable and (.name | startswith("iPhone"))) | .udid] | first // empty' "$evidence/available-simulators.json")"
[[ -n "$device" ]] || { echo "No available iOS $ios_major iPhone simulator in this isolated job" >&2; exit 2; }
printf '%s\n' "$device" > "$evidence/simulator-udid.txt"
(
  cd "$package_dir"
  xcodebuild -list -json > "$evidence/schemes.json"
)
scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
schemes = data.get("workspace", {}).get("schemes", []) + data.get("project", {}).get("schemes", [])
for candidate in ("ComposerValidation-Package", "ComposerValidation", "AI_Hanlin"):
    if candidate in schemes:
        print(candidate)
        break
else:
    raise SystemExit(f"No known Composer package test scheme; discovered {schemes}")
PY
)"
printf '%s\n' "$scheme" > "$evidence/scheme.txt"

set +e
(
  cd "$package_dir"
  xcodebuild test -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$scratch/DerivedData" \
    -resultBundlePath "$evidence/Composer.xcresult" \
    -only-testing:AI_HanlinTests/HanlinMorphComposerTests \
    -only-testing:AI_HanlinTests/NativeComposerLineSizingTests
) 2>&1 | tee "$evidence/xcodebuild.log"
build_status=${PIPESTATUS[0]}
set -e
printf '{"xcodebuild_exit_code":%s}\n' "$build_status" > "$evidence/process-status.json"
xcrun xcresulttool get test-results tests --path "$evidence/Composer.xcresult" --format json > "$evidence/tests.json"
[[ "$build_status" == 0 ]] || exit "$build_status"
python3 Scripts/CI/ComposerValidation/verify_results.py "$evidence/tests.json" \
  --inputs "$evidence/proof-inputs.json" | tee "$evidence/verified-cases.txt"
