#!/usr/bin/env bash
set -euo pipefail

# Compile actual, self-contained production sources. No native engine, stub or
# alternate application implementation is linked by this focused SDK check.
readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly EVIDENCE="${RUNNER_TEMP:?}/runtime-job-foundation-evidence"
readonly WORK="$(mktemp -d "${RUNNER_TEMP}/hanlin-runtime-foundation.XXXXXX")"
mkdir -p "$EVIDENCE" "$WORK/Sources/RuntimeJobs" "$WORK/Tests/RuntimeJobTests"
cd "$REPOSITORY_ROOT"
git rev-parse HEAD > "$EVIDENCE/source-commit.txt"
xcodebuild -version | tee "$EVIDENCE/xcode-version.txt"
xcrun swift --version | tee "$EVIDENCE/swift-version.txt"
readonly SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
readonly TARGET="arm64-apple-ios27.0"
printf '%s\n' "$SDK" "$TARGET" > "$EVIDENCE/sdk-target.txt"

core_sources=()
for name in RuntimeModels RuntimePolicy RuntimeFileLayout RuntimeJobStore RuntimeUserOperation RuntimeCapabilityContract; do
  file="AI_HLY/Downstream/RuntimeCore/Core/$name.swift"
  core_sources+=("$file")
  cp "$file" "$WORK/Sources/RuntimeJobs/"
done
background="AI_HLY/Downstream/RuntimeCore/Core/RuntimeBackgroundContinuation.swift"
shasum -a 256 "${core_sources[@]}" "$background" AI_HLYTests/RuntimeJobInterruptionTests.swift AI_HLYTests/RuntimeUserOperationTests.swift > "$EVIDENCE/source-sha256.txt"
plutil -lint AI-HLY-Info.plist | tee "$EVIDENCE/plist-lint.txt"
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-name HanlinRuntimeFoundation -sdk "$SDK" -target "$TARGET" \
  "${core_sources[@]}" "$background" 2>&1 | tee "$EVIDENCE/ios-sdk-typecheck.log"

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RuntimeJobFoundationProof", platforms: [.macOS(.v15)], targets: [
    .target(name: "RuntimeJobs"),
    .testTarget(name: "RuntimeJobTests", dependencies: ["RuntimeJobs"])
])
SWIFT
python3 - "$WORK" <<'PYTHON'
from pathlib import Path
import sys
work = Path(sys.argv[1])
for name in ("RuntimeJobInterruptionTests", "RuntimeUserOperationTests"):
    text = (Path("AI_HLYTests") / (name + ".swift")).read_text(encoding="utf-8")
    assert text.count("@testable import AI_Hanlin") == 1
    (work / "Tests/RuntimeJobTests" / (name + ".swift")).write_text(
        text.replace("@testable import AI_Hanlin", "@testable import RuntimeJobs"), encoding="utf-8")
PYTHON
swift test --package-path "$WORK" --filter 'Runtime(JobInterruption|UserOperation)Tests' 2>&1 | tee "$EVIDENCE/executed-tests.log"
python3 - "$EVIDENCE/executed-tests.log" <<'PYTHON'
from pathlib import Path
import re, sys
text = re.sub(r"\x1b\[[0-9;]*m", "", Path(sys.argv[1]).read_text(encoding="utf-8"))
required = [
    "nativeCompletionReadsRootInterruptionEvenBeforeItsAsyncNotification",
    "lateNativeCompletionPreservesSystemInterruptionAndPartialOutput",
    "completedJobsRejectLateFailureAndInterruptionReclassification",
    "interruptionIsFirstCauseAndCallbacksMayReenterWithoutDeadlock",
    "actualProgressUsesJournalHighWaterMarksWithoutPollInflation",
    "producerOwnsOnlyItsOperationAndClearsTheCancellationCycle",
    "interruptedOriginalStreamNeverFinishesAsSuccessfulEOF",
]
for name in required:
    if not re.search(r"Test " + re.escape(name) + r"\(\) passed", text):
        raise SystemExit("Required executed Swift Testing case missing or not passed: " + name)
if not re.search(r"Test run with 7 tests.*passed", text):
    raise SystemExit("Expected seven actual Swift Testing cases; a green/zero-case XCTest heading is insufficient")
print("Verified all seven executed Foundation ownership tests; iOS SDK typecheck is a separate compile-only proof.")
PYTHON
