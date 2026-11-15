#!/bin/bash
# Actual registered MiniApps project target, existing runtime inputs, focused UI
# and leaf cases. No AI application build or engine build is requested.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
[[ "$(uname -s)" == Darwin ]] || { echo 'Actual Apple host required' >&2; exit 2; }
evidence="$root/build/integration-validation-evidence"
mkdir -p "$evidence"
actual_sha="$(git rev-parse HEAD)"
[[ "${INTEGRATION_EXPECTED_SHA:-}" =~ ^[0-9a-f]{40}$ && "$actual_sha" == "$INTEGRATION_EXPECTED_SHA" ]] || {
  echo 'Exact provider checkout SHA mismatch' >&2; exit 2;
}
printf '%s\n' "$actual_sha" > "$evidence/source-commit.txt"
baseline=dd700c03e9fe9d22e95a031d4684275512ee6e6f
if ! git cat-file -e "$baseline^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$baseline"
fi
xcodebuild -version | tee "$evidence/xcode.txt"
xcrun swift --version | tee "$evidence/swift.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$evidence/sdk.txt"
sw_vers > "$evidence/os.txt"
python3 - "$evidence/sdk.txt" <<'PY'
import sys
assert int(open(sys.argv[1]).read().strip().split('.')[0]) >= 27, 'iOS Simulator SDK 27+ required'
PY
python3 Scripts/CI/IntegrationValidation/validate.py > "$evidence/graph.json"
python3 -m unittest discover -s Scripts/CI/IntegrationValidation -p 'test_*.py' -v 2>&1 | tee "$evidence/validator-tests.log"
python3 - <<'PY' > "$evidence/source-sha256.json"
import hashlib,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,'Scripts/CI/IntegrationValidation')
from extract_target import simulator_ci_config
root=Path.cwd();manifest=json.loads(Path('Scripts/CI/IntegrationValidation/miniapps_provider_sources.json').read_text())
paths=manifest['swift_sources']+manifest['native_sources']+[manifest['ui_test_source']]
paths+=['AI_HLY.xcodeproj/project.pbxproj','AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme',
        '.github/workflows/build-ios26-unsigned-ipa.yml','RuntimeDependencies.lock.json']
for prefix in ['HanlinMiniAppsApp','Packages/HanlinPlatform','Packages/HanlinProductSplit',
               'Scripts/CI/IntegrationValidation','Scripts/NativeScript','Scripts/Expo']:
    paths+=subprocess.check_output(['git','ls-files',prefix],text=True).splitlines()
hashes={}
for path in sorted(set(paths)):
    data=Path(path).read_bytes()
    assert data==subprocess.check_output(['git','show',f'HEAD:{path}']),path
    hashes[path]=hashlib.sha256(data).hexdigest()
config=simulator_ci_config(root)
assert not Path('Config.xcconfig').exists(), 'Do not overwrite an existing configuration'
Path('Config.xcconfig').write_text(config)
Path('build/integration-validation-evidence/CI-Config.xcconfig').write_text(config)
print(json.dumps(hashes,indent=2))
PY
retain_locks() {
  local process_status="$1"
  python3 - "$evidence" "$process_status" <<'PY'
import hashlib,json,os,sys
from pathlib import Path
evidence=Path(sys.argv[1]);folder=evidence/'raw-locks';folder.mkdir(exist_ok=True);records=[]
for root in ['AI_HLY.xcodeproj','Packages/HanlinProductSplit']:
    for directory,folders,files in os.walk(root):
        folders[:]=[name for name in folders if name not in ['.build','.git']]
        if 'Package.resolved' not in files:continue
        path=Path(directory)/'Package.resolved';data=path.read_bytes();raw=folder/f'{len(records):02d}-Package.resolved';raw.write_bytes(data)
        records.append({'source_path':str(path),'raw_file':str(raw.relative_to(evidence)),
                        'sha256':hashlib.sha256(data).hexdigest(),'resolved':json.loads(data)})
(evidence/'resolution.json').write_text(json.dumps(records,indent=2))
(evidence/'process-status.json').write_text(json.dumps({'exit_code':int(sys.argv[2]),'scope':'actual wired MiniApps target, two UI cases and six leaf cases'}))
PY
}
trap 'retain_locks "$?"' EXIT
# Existing pinned download/preparation routes. These do not build a replacement
# runtime engine, copy another app, or replace implementation dependencies.
npm ci --ignore-scripts --no-audit --no-fund --prefix Scripts/NativeScript 2>&1 | tee "$evidence/nativescript-install.log"
npm run prepare:ios-dependencies --prefix Scripts/NativeScript 2>&1 | tee "$evidence/nativescript-inputs.log"
npm ci --ignore-scripts --no-audit --no-fund --prefix Scripts/Expo 2>&1 | tee "$evidence/expo-install.log"
node Scripts/Expo/prepare-ios-dependencies.mjs 2>&1 | tee "$evidence/expo-inputs.log"
bash Scripts/Runtime/prepare-runtime-core.sh 2>&1 | tee "$evidence/runtime-inputs.log"
cp AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json "$evidence/RuntimeManifest.json"
cp build/nativescript-metadata-tool/provenance.json "$evidence/metadata-tool-provenance.json"
python3 - <<'PY' > "$evidence/prepared-resource-sha256.json"
import hashlib,json
from pathlib import Path
manifest=json.loads(Path('Scripts/CI/IntegrationValidation/miniapps_provider_sources.json').read_text())
paths=[Path(path) for path in manifest['resources']]
for root in ['Packages/HanlinNativeScriptRuntime/Artifacts','Packages/HanlinExpoRuntime/Artifacts']:
    paths+=list(Path(root).rglob('.artifact-manifest.json'))
for path in paths:
    assert path.is_file(),f'Missing real resource: {path}'
print(json.dumps({str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},indent=2))
PY
xcrun simctl list devices available -j > "$evidence/simulators.json"
device="$(python3 - "$evidence/simulators.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
print(next(d['udid'] for runtime,ds in data['devices'].items() if 'iOS-27' in runtime
           for d in ds if d['isAvailable'] and d['name'].startswith('iPhone')))
PY
)"
printf '%s\n' "$device" > "$evidence/simulator-udid.txt"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/hanlin-miniapps-provider.XXXXXXXX")"
set +e
xcodebuild test -project AI_HLY.xcodeproj -scheme HanlinMiniApps -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
  -resultBundlePath "$evidence/ProviderUI.xcresult" \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:HanlinMiniAppsUITests/MiniAppsProviderUITests CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/provider-ui.log"
ui_status=${PIPESTATUS[0]}
set -e
if [[ -d "$evidence/ProviderUI.xcresult" ]]; then
  xcrun xcresulttool get test-results tests --path "$evidence/ProviderUI.xcresult" --format json > "$evidence/ui-tests.json" || true
fi
[[ "$ui_status" == 0 ]] || exit "$ui_status"
python3 Scripts/CI/IntegrationValidation/verify_results.py "$evidence/ui-tests.json" --miniapps-ui | tee "$evidence/verified-ui.json"
(
  cd Packages/HanlinProductSplit
  xcodebuild -list -json > "$evidence/package-schemes.json"
)
scheme="$(python3 - "$evidence/package-schemes.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]));schemes=data.get('workspace',{}).get('schemes',[])+data.get('project',{}).get('schemes',[])
print(next(s for s in ['HanlinProductSplit-Package','HanlinProductSplit'] if s in schemes))
PY
)"
(
  cd Packages/HanlinProductSplit
  xcodebuild test -scheme "$scheme" -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$scratch/LeafDerivedData" -resultBundlePath "$evidence/SplitTests.xcresult" \
    -only-testing:RegisteredIntegrationTests/RegisteredSplitIntegrationTests CODE_SIGNING_ALLOWED=NO
) 2>&1 | tee "$evidence/leaf-tests.log"
xcrun xcresulttool get test-results tests --path "$evidence/SplitTests.xcresult" --format json > "$evidence/tests.json"
python3 Scripts/CI/IntegrationValidation/verify_results.py "$evidence/tests.json" | tee "$evidence/verified-cases.json"
python3 - <<'PY' > "$evidence/engine-availability.json"
import json
print(json.dumps({'swift':'compiled canonical Swift Parity app launched in UI test',
                  'nativeScript':'existing source and SDK linked; actual app execution NOT_RUN',
                  'expo':'existing source and SDK linked; actual app execution NOT_RUN',
                  'scriptUI':'existing source and SDK linked; actual app execution NOT_RUN',
                  'cross_app_transport':'NOT_RUN; authenticated mailbox binding absent',
                  'ai_assistant':'unconfigured by design in MiniApps'},indent=2))
PY
retain_locks 0
