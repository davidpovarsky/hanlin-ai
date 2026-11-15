#!/usr/bin/env python3
"""Scope the long native test-driver allowance to the real >300s obligation."""
import argparse


LONG_SUITE = "AI_HLYTests/RuntimeAutonomyV3Tests"
LONG_METHOD = LONG_SUITE + "/embeddedNodeAndPythonActuallyRunBeyondThreeHundredSeconds"


def unit_allowance(selectors: str) -> int:
    selected = {s.strip().removesuffix("()") for s in selectors.split(",") if s.strip()}
    return 660 if selected & {"AI_HLYTests", LONG_SUITE, LONG_METHOD} else 300


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selectors", required=True)
    print(unit_allowance(parser.parse_args().selectors))
