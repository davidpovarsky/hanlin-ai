#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="$root/build/chat-motion-component-evidence"
mkdir -p "$evidence"
started=$SECONDS
phase=preflight
phase_started=$SECONDS
finish_phase(){ printf '%s\n' "$((SECONDS-phase_started))" > "$evidence/$phase-duration-seconds.txt";phase="$1";phase_started=$SECONDS; }
retain(){
  status=$?;last_phase="$phase";finish_phase diagnostics
  printf 'exit_code=%s\nphase=%s\nduration_seconds=%s\n' "$status" "$last_phase" "$((SECONDS-started))" > "$evidence/process-status.txt"
  python3 "$root/Scripts/CI/generate_performance_report.py" --log-dir "$evidence" \
    --run-id "${GITHUB_RUN_ID:-}" --commit-sha "$(git -C "$root" rev-parse HEAD)" --event-name workflow_dispatch \
    --output-json "$evidence/ci-performance-report.json" --step-summary "${GITHUB_STEP_SUMMARY:-$evidence/step-summary.md}"
  return "$status"
}
trap retain EXIT
git rev-parse HEAD > "$evidence/source-sha.txt"
selected_xcode="$(python3 - <<'PY'
import glob,re
paths=[p for p in glob.glob('/Applications/Xcode*.app') if re.search(r'/Xcode[_-]27(?:[._][0-9]+)*\.app$',p)]
paths.sort(key=lambda p:tuple(map(int,re.findall(r'[0-9]+',p))))
print(paths[-1] if paths else '')
PY
)"
[[ -n "$selected_xcode" ]] || { echo 'INFRA_ERROR: no stable Xcode27'; exit 2; }
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
xcodebuild -version > "$evidence/xcode.txt"
xcrun swift --version > "$evidence/swift.txt"
sw_vers > "$evidence/os.txt"
finish_phase compile
files=(AI_HLY/Downstream/ChatPresentation/ChatMotionConfiguration.swift
       AI_HLY/Downstream/ChatPresentation/ChatMotionPreferences.swift
       AI_HLY/Downstream/ChatPresentation/HanlinAnimatedDisclosure.swift)
shasum -a 256 "${files[@]}" docs/chat-motion/ChatMotionModelChecks.swift > "$evidence/input-hashes.txt"
for sdk in iphonesimulator iphoneos; do
  target=arm64-apple-ios26.0
  [[ "$sdk" == iphonesimulator ]] && target=arm64-apple-ios26.0-simulator
  xcrun --sdk "$sdk" --show-sdk-version > "$evidence/$sdk.txt"
  xcrun --sdk "$sdk" swiftc -emit-module -module-name HanlinChatMotion \
    -emit-module-path "$evidence/$sdk.swiftmodule" -target "$target" \
    -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" "${files[@]}" \
    2>&1 | tee "$evidence/$sdk-compile.log"
done
finish_phase model-checks
xcrun swiftc -parse-as-library "${files[0]}" docs/chat-motion/ChatMotionModelChecks.swift -o "$evidence/model-checks"
"$evidence/model-checks" | tee "$evidence/model-checks.log"
finish_phase complete
printf '%s\n' 'COMPILE_PASS simulator/device; portable model checks EXECUTED_PASS; UI/app acceptance NOT_RUN' > "$evidence/result.txt"
