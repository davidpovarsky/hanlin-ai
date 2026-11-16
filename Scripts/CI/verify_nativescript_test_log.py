"""Check native log evidence belonging to the exact selected original UI tests."""
import argparse
from pathlib import Path
import re

SUITE = "AI_HLYUITests/HanlinNativeScriptProductionE2ETests"
PERFORMANCE = "AI_HLYUITests/HanlinUIPerformanceUITests"
CORE = SUITE + "/testProductionSharedCoreUnbundledEndToEnd"
SWIFTUI = SUITE + "/testProductionSwiftUIInteractionCoreRegressionAndLifecycle"
REJECTIONS = {SUITE + "/testUnsupportedPluginRejection", SUITE + "/testMalformedPackageRejection"}
CORE_MARKERS = (
    "HANLIN_NS_FIXTURE_STARTED", "HANLIN_NS_NATIVE_API_OK", "HANLIN_NS_SCRIPTING_ADAPTER_OK",
    "HANLIN_NS_MODULE_RESOURCE_OK", "HANLIN_NS_CORE_UI_READY controls=Label,Button",
)
SWIFTUI_MARKERS = (
    "HANLIN_NS_SWIFTUI_MODULE_OK package=@nativescript/swift-ui version=4.0.2",
    "HANLIN_NS_SWIFTUI_PROVIDER_READY", "HANLIN_NS_SWIFTUI_DATA_OK",
    "HANLIN_NS_SWIFTUI_EVENT_OK count=1 source=swiftui",
)


def required_markers(selectors):
    selected = {s.strip().removesuffix("()") for s in selectors.split(",") if s.strip()}
    whole = not selected or bool(selected & {"AI_HLYUITests", SUITE})
    performance = any(s == PERFORMANCE or s.startswith(PERFORMANCE + "/") for s in selected)
    native = whole or performance or any(s.startswith(SUITE + "/") and s not in REJECTIONS for s in selected)
    core = whole or performance or bool(selected & {CORE, SWIFTUI})
    swiftui = whole or performance or SWIFTUI in selected
    markers = ["HANLIN_NS_INITIALIZED_EXTERNAL_ROOT"] if native else []
    if core:
        markers.extend(CORE_MARKERS)
    if swiftui:
        markers.extend(SWIFTUI_MARKERS)
    if core or swiftui:
        markers.append("HANLIN_NS_PRODUCTION_SHUTDOWN_OK")
    return markers


def missing_evidence(log, selectors):
    missing = [marker for marker in required_markers(selectors) if marker not in log]
    if "HANLIN_NS_INITIALIZED_EXTERNAL_ROOT" in required_markers(selectors) and not re.search(
            r"HANLIN_NS_INITIALIZED_EXTERNAL_ROOT path=.*/Library/Application Support/", log):
        missing.append("external root under Library/Application Support")
    return missing


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--selectors", required=True)
    args = parser.parse_args()
    missing = missing_evidence(args.log.read_text(encoding="utf-8", errors="replace"), args.selectors)
    if missing:
        raise SystemExit("Missing selected native UI log evidence: " + ", ".join(missing))
    print("Selected original NativeScript UI log evidence verified.")
