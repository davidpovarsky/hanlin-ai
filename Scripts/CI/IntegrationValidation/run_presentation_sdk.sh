#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/presentation-sdk-evidence"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/tested-source-commit.txt"
selected_xcode="$(python3 Scripts/CI/select_stable_xcode.py)"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version > "$evidence/xcode.txt"
xcrun swift --version > "$evidence/swift.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-presentation.XXXXXXXX")"
# Preserve the sibling path dependency used by HanlinChatUI and the other presentation products.
git archive HEAD Packages/HanlinPresentationSDK Packages/HanlinPlatform > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch"
package="$scratch/Packages/HanlinPresentationSDK"
python3 - "$package" <<'PY' > "$evidence/source-sha256.json"
from pathlib import Path
import hashlib,json,sys
p=Path(sys.argv[1])
print(json.dumps({str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()},indent=2))
PY
set +e
xcrun swift test --package-path "$package" > "$evidence/foundation-tests.log" 2>&1
foundation_status=$?
(cd "$package" && xcodebuild build -scheme HanlinChatUI -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/IOSDerivedData" -resultBundlePath "$evidence/IOSBuild.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO) > "$evidence/ios-build.log" 2>&1
ios_status=$?
set -e
printf '{"foundation_test_exit":%s,"ios_build_exit":%s}\n' "$foundation_status" "$ios_status" > "$evidence/process-status.json"
cat "$evidence/process-status.json"
if [[ "$foundation_status" != 0 ]]; then tail -100 "$evidence/foundation-tests.log"; fi
if [[ "$ios_status" != 0 ]]; then tail -120 "$evidence/ios-build.log"; fi
test "$foundation_status" = 0
test "$ios_status" = 0
