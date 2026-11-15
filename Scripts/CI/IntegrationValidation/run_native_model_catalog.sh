#!/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
evidence="${HANLIN_SDK_EVIDENCE_DIRECTORY:-$root/build/agent-sdk-validation-evidence}"
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/tested-source-commit.txt"
started=$SECONDS
trap 'rc=$?; printf "{\"exit\":%s,\"total_seconds\":%s}\n" "$rc" "$((SECONDS-started))" > "$evidence/process-exit.json"' EXIT
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-native-catalog.XXXXXXXX")"
python3 - "$scratch" <<'PY'
import shutil,sys
assert shutil.disk_usage(sys.argv[1]).free >= 8*1024**3, 'Less than 8 GiB runner space'
PY
selected_xcode="$(python3 -c 'import glob,re; p=[p for p in glob.glob("/Applications/Xcode*.app") if re.search(r"/Xcode[_-]27(?:[._][0-9]+)*\.app$",p)]; p.sort(key=lambda x:tuple(map(int,re.findall(r"[0-9]+",x)))); print(p[-1] if p else "")')"
test -n "$selected_xcode"
export DEVELOPER_DIR="$selected_xcode/Contents/Developer"
{ xcodebuild -version; xcrun swift --version; xcrun --sdk macosx --show-sdk-version; xcrun --sdk iphonesimulator --show-sdk-version; uname -m; sw_vers; } > "$evidence/toolchain.txt"
xcrun simctl list runtimes -j > "$evidence/simulator-runtimes.json"
git archive HEAD Packages/HanlinAgentSDK Packages/HanlinPlatform Scripts/CI/NativeModelValidation \
  AI_HLY/Model/AllModels.swift AI_HLY/Model/HanlinAppleModelCatalogAdapter.swift \
  AI_HLY/Downstream/ChatCore/HanlinDefaultChatPolicy.swift \
  AI_HLY/Downstream/ChatPresentation/ProviderModelCatalogMetadata.swift > "$evidence/tested-source.tar"
tar -xf "$evidence/tested-source.tar" -C "$scratch"
package="$scratch/NativeCatalog"
mkdir -p "$package/Sources/HanlinNativeModelCatalog" "$package/Tests/HanlinNativeModelCatalogTests"
cp "$scratch/Scripts/CI/NativeModelValidation/Package.swift" "$package/Package.swift"
cp "$scratch/Scripts/CI/NativeModelValidation/NativeModelCatalogTests.swift" "$package/Tests/HanlinNativeModelCatalogTests/"
cp "$scratch/AI_HLY/Model/AllModels.swift" "$scratch/AI_HLY/Model/HanlinAppleModelCatalogAdapter.swift" \
  "$scratch/AI_HLY/Downstream/ChatCore/HanlinDefaultChatPolicy.swift" \
  "$scratch/AI_HLY/Downstream/ChatPresentation/ProviderModelCatalogMetadata.swift" "$package/Sources/HanlinNativeModelCatalog/"
python3 - "$scratch" "$package" <<'PY' > "$evidence/source-binding.json"
import hashlib,json,subprocess,sys
from pathlib import Path
scratch,package=map(Path,sys.argv[1:]);records={}
for path in subprocess.check_output(['git','ls-tree','-r','--name-only','HEAD','Packages/HanlinAgentSDK','Packages/HanlinPlatform','Scripts/CI/NativeModelValidation','AI_HLY/Model/AllModels.swift','AI_HLY/Model/HanlinAppleModelCatalogAdapter.swift','AI_HLY/Downstream/ChatCore/HanlinDefaultChatPolicy.swift','AI_HLY/Downstream/ChatPresentation/ProviderModelCatalogMetadata.swift'],text=True).splitlines():
 raw=(scratch/path).read_bytes();assert raw==subprocess.check_output(['git','show',f'HEAD:{path}']);records[path]=hashlib.sha256(raw).hexdigest()
for source in (package/'Sources/HanlinNativeModelCatalog').glob('*.swift'):
 original=next(scratch.glob('AI_HLY/**/'+source.name));assert source.read_bytes()==original.read_bytes()
print(json.dumps(records,indent=2))
PY
xcrun swift package --package-path "$package" resolve > "$evidence/resolve.log" 2>&1
(cd "$package" && xcodebuild -list -json) > "$evidence/schemes.json"
scheme="$(python3 - "$evidence/schemes.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));names=d.get('workspace',{}).get('schemes',[])+d.get('project',{}).get('schemes',[])
print(next(x for x in ['HanlinNativeModelCatalog-Package','HanlinNativeModelCatalog'] if x in names))
PY
)"
set +e
(cd "$package" && xcodebuild test -scheme "$scheme" -destination 'platform=macOS' \
  -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$evidence/NativeCatalogTests.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:HanlinNativeModelCatalogTests/NativeModelCatalogTests) > "$evidence/native-catalog-tests.log" 2>&1
test_status=$?
(cd "$package" && xcodebuild build -scheme HanlinNativeModelCatalog -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/IOSDerivedData" -resultBundlePath "$evidence/NativeCatalogIOSBuild.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO) > "$evidence/native-catalog-ios-build.log" 2>&1
build_status=$?
set -e
printf '{"test_exit":%s,"ios_build_exit":%s}\n' "$test_status" "$build_status" > "$evidence/process-status.json"
if [[ -d "$evidence/NativeCatalogTests.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/NativeCatalogTests.xcresult" --format json > "$evidence/NativeCatalogTests.json" || true
fi
python3 - "$evidence" <<'PY' | tee "$evidence/summary.json"
import json,sys
from pathlib import Path
sys.path.insert(0,'Scripts/CI/IntegrationValidation')
from xcresult_to_xunit import nodes
root=Path(sys.argv[1]);status=json.loads((root/'process-status.json').read_text())
try: cases=[n for n in nodes(json.loads((root/'NativeCatalogTests.json').read_text())) if n.get('nodeType')=='Test Case']
except (OSError,ValueError): cases=[]
expected={'registrationIsIdempotentAndAppendsWithoutReorderingExistingRows','reservedNameConflictPreservesOriginalCatalog','nativeConfigurationUsesActualAvailabilityWithoutCredentialsOrFallback'}
actual={c.get('nodeIdentifier','').split('/')[-1].split('(')[0] for c in cases}
passed=actual==expected and len(cases)==3 and all(c.get('result')=='Passed' for c in cases) and all(v==0 for v in status.values())
classification='EXECUTED_PASS' if passed else 'TEST_FAILED' if status['test_exit'] and cases else 'BUILD_FAILED' if status['test_exit'] or status['ios_build_exit'] else 'INFRA_ERROR'
print(json.dumps({'status':classification,'scope':'actual app SwiftData model + native catalog adapter, Mac package tests/iOS compile; no APIManager/UI/device generation claim','process_status':status,'cases':cases},indent=2))
sys.exit(0 if passed else 1)
PY
