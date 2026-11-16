"""Choose an iPad on an on-disk runtime matching the actual selected stable SDK."""
import argparse
import json
from pathlib import Path
import subprocess


def select(devices: dict, runtimes: dict, sdk: str) -> dict:
    canonical = "com.apple.CoreSimulator.SimRuntime.iOS-" + sdk.replace(".", "-")
    candidates = []
    for runtime in runtimes["runtimes"]:
        if runtime.get("platform") != "iOS" or runtime.get("version") != sdk or not runtime.get("isAvailable"):
            continue
        if not Path(runtime["runtimeRoot"]).is_dir() or not (Path(runtime["bundlePath"]) / "Contents/Info.plist").is_file():
            continue
        for device in devices["devices"].get(runtime["identifier"], []):
            if device.get("isAvailable") and "iPad" in device.get("name", ""):
                priority = (runtime["identifier"] == canonical, "iPad Pro 13" in device["name"], device["name"], device["udid"])
                candidates.append((priority, {"sdk": sdk, "runtime": runtime, "device": device}))
    if not candidates:
        raise RuntimeError("No available iPad on an installed runtime matching the stable SDK")
    return max(candidates, key=lambda value: value[0])[1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tsv", action="store_true")
    parser.add_argument("--create-owned")
    args = parser.parse_args()
    def read(command):
        return subprocess.check_output(command, text=True, timeout=20)
    sdk = read(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).strip()
    devices = json.loads(read(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtimes = json.loads(read(["xcrun", "simctl", "list", "runtimes", "-j"]))
    selected = select(devices, runtimes, sdk)
    if args.create_owned:
        if not args.create_owned.startswith("Hanlin-Phase2-") or len(args.create_owned) > 120:
            raise ValueError("A bounded Phase2-owned simulator name is required")
        original = selected["device"]
        identifier = read(["xcrun", "simctl", "create", args.create_owned,
                           original["deviceTypeIdentifier"], selected["runtime"]["identifier"]]).strip()
        selected["source_device"] = original
        selected["model"] = original["name"]
        selected["device"] = {**original, "udid": identifier, "name": args.create_owned, "state": "Shutdown"}
        selected["device"].pop("dataPath", None)
        selected["device"].pop("logPath", None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({**selected, "observed_runtimes": runtimes}, indent=2))
    device, runtime = selected["device"], selected["runtime"]
    print("\t".join([device["udid"], selected.get("model", device["name"]), runtime["identifier"]]) if args.tsv else device["udid"])
