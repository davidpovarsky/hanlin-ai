"""LLDB command: observe real same-thread PP Lex, snapshot, then kill owned target."""
import hashlib
import json
from pathlib import Path
import shlex

import lldb


def file_path(spec):
    return str(Path(spec.GetDirectory() or "") / (spec.GetFilename() or ""))


def cancel(debugger, command, result, unused):
    config = json.loads(Path(shlex.split(command)[0]).read_text())
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    facts = {"status": "NOT_OBSERVED", "pid": process.GetProcessID(),
             "stopped": process.GetState() == lldb.eStateStopped, "threads": []}
    expected = str(Path(config["executable"]).resolve())
    receipt = Path(config["receipt"])
    output = Path(config["output"])

    def snapshot(label):
        exists = receipt.exists()
        body = receipt.read_bytes() if exists else b""
        (output.parent / (label + ".receipt.raw")).write_bytes(body)
        return {"exists": exists, "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}

    try:
        actual = file_path(process.GetProcessInfo().GetExecutable())
        facts["processExecutable"] = actual
        facts["selectedExecutable"] = file_path(target.GetExecutable())
        facts["executableSHA256"] = hashlib.sha256(Path(actual).read_bytes()).hexdigest()
        owned = str(Path(actual).resolve()) == expected and facts["executableSHA256"] == config["binarySHA256"]
        facts["ownedExecutable"] = owned
        eligible = False
        if owned and facts["stopped"]:
            for thread in process:
                frames = [{"function": frame.GetFunctionName() or "", "module": file_path(frame.GetModule().GetFileSpec())}
                          for frame in list(thread)[:128]]
                facts["threads"].append({"id": thread.GetThreadID(), "frames": frames})
                lex = any("clang::Preprocessor::Lex(" in frame["function"] for frame in frames)
                action = any("HanlinProvenanceAction::ExecuteAction" in frame["function"] and
                             str(Path(frame["module"]).resolve()) == expected for frame in frames)
                if lex and action:
                    eligible = True
                    facts["observedThread"] = thread.GetThreadID()
        facts["beforeKillReceipt"] = snapshot("debugger.immediately-before-kill")
        facts["unfinishedEstablished"] = eligible and not facts["beforeKillReceipt"]["exists"]
        # Cleanup only the verified actual owned executable. No attach/PID guess.
        if owned and process.GetState() == lldb.eStateStopped:
            error = process.Kill()
            facts.update(killSucceeded=error.Success(), killError=str(error),
                         exited=process.GetState() == lldb.eStateExited,
                         exitStatus=process.GetExitStatus(), exitDescription=process.GetExitDescription())
        facts["afterKillReceipt"] = snapshot("debugger.after-kill")
        if facts["unfinishedEstablished"] and facts.get("killSucceeded") and facts.get("exited"):
            facts["status"] = "OBSERVED_CANCELLED"
    except Exception as error:
        facts["reason"] = type(error).__name__ + ": " + str(error)
    finally:
        output.write_text(json.dumps(facts, indent=2) + "\n")
        result.PutCString("Retained actual debugger cancellation observation: " + facts["status"])


def __lldb_init_module(debugger, unused):
    debugger.HandleCommand("command script add -f " + __name__ + ".cancel hanlin-cancel")
