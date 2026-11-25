from pathlib import Path
import copy, hashlib, json, re, subprocess
import yaml
EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[3]
RELATIVE = ".github/workflows/build-ios26-unsigned-ipa.yml"
BASE = "ce876c32a9dd0f3c324222f549c4642c13f8a700"
before = subprocess.check_output(["git", "show", BASE + ":" + RELATIVE], cwd=ROOT, text=True)
after = (ROOT / RELATIVE).read_text()
expected, count = re.subn(r"(?m)^[ \t]+SWIFT_ENABLE_EXPLICIT_MODULES=NO \\\n", "", before)
assert count == 4, count
assert after == expected, "Only the four command-line NO arguments may change"
old, new = yaml.safe_load(before), yaml.safe_load(after)
expected_workflow = copy.deepcopy(old)
results = []
for job_id, job in old["jobs"].items():
    for index, step in enumerate(job.get("steps", [])):
        script = step.get("run", "")
        if "SWIFT_ENABLE_EXPLICIT_MODULES=NO" not in script:
            continue
        expected_script, found = re.subn(r"(?m)^[ \t]+SWIFT_ENABLE_EXPLICIT_MODULES=NO \\\n", "", script)
        assert found == 1
        actual = new["jobs"][job_id]["steps"][index]["run"]
        assert actual == expected_script
        expected_workflow["jobs"][job_id]["steps"][index]["run"] = actual
        label = str(len(results) + 1)
        (EVIDENCE / (label + "-before.sh")).write_text(script)
        (EVIDENCE / (label + "-after.sh")).write_text(actual)
        # GitHub expressions are interpolated by Actions before invoking Bash;
        # use an inert token for syntax parsing only. No shell body is executed.
        checked = re.sub(r"\$\{\{.*?\}\}", "GITHUB_EXPRESSION", actual, flags=re.S)
        path = EVIDENCE / (label + "-syntax.sh")
        path.write_text(checked)
        command = ["bash", "--noprofile", "--norc", "-n", str(path)]
        result = subprocess.run(command, capture_output=True, text=True)
        (EVIDENCE / (label + "-syntax.stdout.log")).write_text(result.stdout)
        (EVIDENCE / (label + "-syntax.stderr.log")).write_text(result.stderr)
        assert result.returncode == 0, (step.get("name"), result.stderr)
        results.append({"job": job_id, "stepIndex": index, "stepName": step.get("name"),
            "project": job.get("env", {}).get("PROJECT_PATH"),
            "scheme": job.get("env", {}).get("SCHEME_NAME"),
            "configuration": job.get("env", {}).get("CONFIGURATION"),
            "beforeSHA256": hashlib.sha256(script.encode()).hexdigest(),
            "afterSHA256": hashlib.sha256(actual.encode()).hexdigest(),
            "removedArgument": "SWIFT_ENABLE_EXPLICIT_MODULES=NO",
            "allOtherRunBytesUnchanged": True, "syntaxCommand": command,
            "syntaxExitCode": result.returncode})
assert len(results) == 4
assert new == expected_workflow, "No other workflow value may change"
report = {"baseCommit": BASE, "path": RELATIVE,
    "beforeSHA256": hashlib.sha256(before.encode()).hexdigest(),
    "afterSHA256": hashlib.sha256(after.encode()).hexdigest(),
    "yamlParsed": True, "exactFourLineRemoval": True,
    "allOtherWorkflowFieldsUnchanged": True, "changedCommands": results,
    "executionBoundary": "YAML parse, exact source/parsed-workflow delta, and four Bash syntax checks only. No workflow body, Xcode command, compiler probe, app build or native test executed."}
(EVIDENCE / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"yaml": "PASS", "exactFourArgumentRemoval": "PASS", "changedBashBodies": 4,
                  "bashSyntaxPassed": 4, "nativeExecution": "NOT_RUN"}, indent=2))
