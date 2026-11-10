#!/usr/bin/env python3
"""Check main-app virtual-addressing requirements before/after authorized signing.

The caller supplies plists decoded by security cms / codesign. This checks their
contract, not their cryptographic signatures or physical-device allocation.
"""
import argparse
import json
from pathlib import Path
import plistlib

EXTENDED_VA = "com.apple.developer.kernel.extended-virtual-addressing"


def verify(lock, requested, profile, signed=None):
    compressed = lock.get("node", {}).get("buildConfiguration", {}).get("pointerCompression") is True
    required = compressed or requested.get(EXTENDED_VA) is True
    if compressed and requested.get(EXTENDED_VA) is not True:
        raise ValueError("The configured compressed-pointer V8 cage requires the main app's Extended Virtual Addressing entitlement.")
    if required and profile.get("Entitlements", {}).get(EXTENDED_VA) is not True:
        raise ValueError("The main provisioning profile does not authorize Extended Virtual Addressing. Enable the capability and regenerate the main profile before signing this runtime; do not drop the entitlement.")
    if required and signed is not None and signed.get(EXTENDED_VA) is not True:
        raise ValueError("The actual signed main app lost its required Extended Virtual Addressing entitlement.")
    return {"pointerCompressionConfigured": compressed, "extendedVirtualAddressingRequired": required,
            "profileAuthorizesExtendedVA": profile.get("Entitlements", {}).get(EXTENDED_VA) is True,
            "signedExtendedVA": None if signed is None else signed.get(EXTENDED_VA) is True,
            "physicalAllocationVerified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path("RuntimeDependencies.lock.json"))
    parser.add_argument("--requested", type=Path, default=Path("AI_HLY/AI_HLY.entitlements"))
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--signed", type=Path)
    args = parser.parse_args()
    load_plist = lambda path: plistlib.loads(path.read_bytes())
    try:
        report = verify(json.loads(args.lock.read_bytes()), load_plist(args.requested), load_plist(args.profile),
                        None if args.signed is None else load_plist(args.signed))
    except ValueError as error:
        raise SystemExit(str(error)) from None
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
