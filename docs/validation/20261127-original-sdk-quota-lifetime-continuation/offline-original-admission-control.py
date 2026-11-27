"""Run the new admission against the already-downloaded original failed artifact.

This executes Python validation only. Source/test binaries remain inert. The
current inventory is a reviewed-source replay fixture, not a new hosted build.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent
HERE = ROOT / "lifetime-continuation-after/Scripts/CI/SDKSourceValidation"
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("lifetime_admission_control", HERE / "run.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
from continuation import validate_api, validate_source_continuity
from quota_continuation import admit_quota_archive

fixed = control.CONFIG["quotaContinuation"]
source, = fixed["reviewedSourceSuccessors"]
original = json.loads((HERE / "Fixtures/original-45963272356-source-files.json").read_text())
change, = fixed["reviewedSourceSuccessors"][source]["inventoryChanges"]
current = [change["after"] if x["path"] == change["before"]["path"] else x for x in original]
new_test = (HERE / "Fixtures/reviewed-0ae-quota-test.swift").read_bytes()
assert control.blob_sha(new_test) == change["after"]["blob"]
assert hashlib.sha256(new_test).hexdigest() == change["after"]["sha256"]
api = json.loads((HERE / "Fixtures/original-45963272356-api-identities.json").read_text())
validate_api(api["run"], api["jobs"], api["artifact"], fixed)
agent = control.CONFIG["continuation"]
agent_original = json.loads((HERE / "Fixtures/original-45954793309-source-files.json").read_text())
agent_continuity = validate_source_continuity(agent_original, current, source, agent)

archive = ROOT / "actual-run-45963272356-1/artifact-15181687501.zip"
output = ROOT / "lifetime-continuation-original-admission"
output.mkdir(exist_ok=False)
prefix = f'{fixed["runID"]}-{fixed["attempt"]}/'
with zipfile.ZipFile(archive) as bundle:
    with bundle.open(prefix + "original-source.tar") as stream, tarfile.open(fileobj=stream, mode="r|") as original_tar:
        matching = [original_tar.extractfile(member).read() for member in original_tar
                    if member.isfile() and member.name == control.APP_LOCK]
assert len(matching) == 1
lock_bytes = matching[0]
row, = [x for x in original if x["path"] == control.APP_LOCK]
assert len(lock_bytes) == row["bytes"] and control.blob_sha(lock_bytes) == row["blob"]
assert hashlib.sha256(lock_bytes).hexdigest() == row["sha256"]
lock_path = output / "original-published-App-Package.resolved"
lock_path.write_bytes(lock_bytes)
admission = admit_quota_archive(archive, output, fixed, current, control.lock_records(lock_path),
    control, source, new_test)
result = {"status": "PASS_ORIGINAL_ARTIFACT_CONTROL_ADMISSION_ONLY", "currentSource": source,
    "originalFailedRun": fixed["runID"], "quotaAdmission": admission,
    "agentSourceContinuity": agent_continuity,
    "scope": "Actual original archive, raw outcomes, dependency and retained product bytes were read and checked. Current source inventory is the exact reviewed one-row fixture. No Swift test, product or compiler was executed; one corrected quota case, Widget2 and iOS remain NOT_RUN."}
(output / "actual-original-admission.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(json.dumps({"status": result["status"], "originalQuota": admission["admission"]["originalQuotaResult"],
    "admittedOldPasses": admission["parsed"]["methodCount"], "compiledOriginalProductFiles": len(admission["product"]["files"]),
    "newSwiftExecutions": 0}))
