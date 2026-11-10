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
for name in RuntimeModels RuntimePolicy RuntimeFileLayout RuntimeJobStore RuntimeUserOperation RuntimeCapabilityContract RuntimeExecutionInputArtifact RuntimeQueuedExecution; do
  file="AI_HLY/Downstream/RuntimeCore/Core/$name.swift"
  core_sources+=("$file")
  cp "$file" "$WORK/Sources/RuntimeJobs/"
done
for file in AI_HLY/Downstream/RuntimeCore/Environment/RuntimeEnvironment.swift AI_HLY/Downstream/RuntimeCore/JavaScriptCore/JavaScriptCoreRuntimeService.swift AI_HLY/Downstream/RuntimeCore/JavaScriptCore/JavaScriptCoreOutputCapture.swift; do
  core_sources+=("$file")
  cp "$file" "$WORK/Sources/RuntimeJobs/"
done
background="AI_HLY/Downstream/RuntimeCore/Core/RuntimeBackgroundContinuation.swift"
shasum -a 256 "${core_sources[@]}" "$background" AI_HLYTests/RuntimeJobInterruptionTests.swift AI_HLYTests/RuntimeUserOperationTests.swift AI_HLYTests/RuntimeExecutionInputArtifactTests.swift AI_HLYTests/RuntimeJavaScriptCoreTests.swift > "$EVIDENCE/source-sha256.txt"
plutil -lint AI-HLY-Info.plist | tee "$EVIDENCE/plist-lint.txt"
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-name HanlinRuntimeFoundation -sdk "$SDK" -target "$TARGET" \
  "${core_sources[@]}" "$background" 2>&1 | tee "$EVIDENCE/ios-sdk-typecheck.log"

# Use the exact locked iOS Python framework's real headers for the production
# Objective-C++ bridge and thread/cancellation owners. This is compile-only:
# no framework rebuild, engine startup, application archive or upload.
readonly PYTHON_URL="$(python3 -c 'import json; print(json.load(open("RuntimeDependencies.lock.json"))["python"]["archive"]["url"])')"
readonly PYTHON_SHA="$(python3 -c 'import json; print(json.load(open("RuntimeDependencies.lock.json"))["python"]["archive"]["sha256"])')"
readonly PYTHON_VERSION="$(python3 -c 'import json; print(json.load(open("RuntimeDependencies.lock.json"))["python"]["version"])')"
mkdir -p "$WORK/python-sdk"
curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --output "$WORK/python-sdk.tar.gz" "$PYTHON_URL"
readonly ACTUAL_PYTHON_SHA="$(shasum -a 256 "$WORK/python-sdk.tar.gz" | awk '{print $1}')"
test "$ACTUAL_PYTHON_SHA" = "$PYTHON_SHA"
tar -xzf "$WORK/python-sdk.tar.gz" -C "$WORK/python-sdk"
grep -Fq "Python version: $PYTHON_VERSION" "$WORK/python-sdk/VERSIONS"
readonly PYTHON_FRAMEWORKS="$WORK/python-sdk/Python.xcframework/ios-arm64"
test -f "$PYTHON_FRAMEWORKS/Python.framework/Headers/Python.h"
printf '%s\n' "$PYTHON_URL" "$PYTHON_VERSION" "$ACTUAL_PYTHON_SHA" > "$EVIDENCE/python-sdk-inputs.txt"
shasum -a 256 AI_HLY/Downstream/RuntimeCore/Python/Native/PythonRuntimeBridge.mm \
  AI_HLY/Downstream/RuntimeCore/Python/Native/PythonRuntimeBridge.h \
  AI_HLY/Downstream/RuntimeCore/Python/Native/PythonCancellationContext.hpp \
  AI_HLY/Downstream/RuntimeCore/Python/Native/PythonThreadOwnership.hpp > "$EVIDENCE/python-bridge-source-sha256.txt"
xcrun clang++ --version > "$EVIDENCE/clang-version.txt"
xcrun clang++ -fsyntax-only -x objective-c++ -fobjc-arc -std=c++17 -Werror \
  -target "$TARGET" -isysroot "$SDK" -F "$PYTHON_FRAMEWORKS" \
  AI_HLY/Downstream/RuntimeCore/Python/Native/PythonRuntimeBridge.mm \
  2>&1 | tee "$EVIDENCE/ios-python-bridge-typecheck.log"
printf '%s\n' "Actual production Objective-C++ bridge typechecked against locked iOS Python $PYTHON_VERSION headers; execution/linking remain separate obligations."

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
for name in ("RuntimeJobInterruptionTests", "RuntimeUserOperationTests", "RuntimeExecutionInputArtifactTests", "RuntimeJavaScriptCoreTests"):
    text = (Path("AI_HLYTests") / (name + ".swift")).read_text(encoding="utf-8")
    assert text.count("@testable import AI_Hanlin") == 1
    (work / "Tests/RuntimeJobTests" / (name + ".swift")).write_text(
        text.replace("@testable import AI_Hanlin", "@testable import RuntimeJobs"), encoding="utf-8")
PYTHON
swift test --package-path "$WORK" --filter 'Runtime(JobInterruption|UserOperation|ExecutionInputArtifact|JavaScriptCore)Tests' 2>&1 | tee "$EVIDENCE/executed-tests.log"
python3 - "$EVIDENCE/executed-tests.log" <<'PYTHON'
from pathlib import Path
import re, sys
text = re.sub(r"\x1b\[[0-9;]*m", "", Path(sys.argv[1]).read_text(encoding="utf-8"))
required = [
    "ordinaryCancellationIsSerializedWithNativeCompletionAndRetainsFinalBytes",
    "largeOriginalSourceAndFullUnicodeOutputSurviveReopenWithoutReplay",
    "explicitDeadlineFailsBeforeJavaScriptOrOutputFilesAreCreated",
    "cancelledQueuedJavaScriptCannotExecuteAfterTheActualRunningContextFinishes",
    "actualRunningJavaScriptRetainsLateBytesAndRootInterruptionUntilNaturalReturn",
    "nativeCompletionReadsRootInterruptionEvenBeforeItsAsyncNotification",
    "lateNativeCompletionPreservesSystemInterruptionAndPartialOutput",
    "completedJobsRejectLateFailureAndInterruptionReclassification",
    "interruptionIsFirstCauseAndCallbacksMayReenterWithoutDeadlock",
    "actualProgressUsesJournalHighWaterMarksWithoutPollInflation",
    "producerOwnsOnlyItsOperationAndClearsTheCancellationCycle",
    "interruptedOriginalStreamNeverFinishesAsSuccessfulEOF",
    "smallControlInputStaysInlineWithoutCreatingAnInbox",
    "largeInputKeepsExactBytesAndDigestAndRejectsAnotherOwnerBeforeSubmission",
]
for name in required:
    if not re.search(r"Test " + re.escape(name) + r"\(\) passed", text):
        raise SystemExit("Required executed Swift Testing case missing or not passed: " + name)
if not re.search(r"Test run with 14 tests.*passed", text):
    raise SystemExit("Expected fourteen actual Swift Testing cases; a green/zero-case XCTest heading is insufficient")
print("Verified all fourteen executed ownership/input/JSC tests; iOS SDK typecheck is a separate compile-only proof.")
PYTHON
