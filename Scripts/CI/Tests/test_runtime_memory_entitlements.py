from pathlib import Path
import json
import plistlib
import unittest

from Scripts.CI.verify_runtime_memory_entitlements import EXTENDED_VA, verify
from Scripts.ProductSplit.extension_inventory import SIGNING_TARGETS


class RuntimeMemoryEntitlementTests(unittest.TestCase):
    def test_actual_repository_main_requests_the_cage_requirement_without_changing_extension_memory(self):
        root = Path(__file__).parents[3]
        lock = json.loads((root / "RuntimeDependencies.lock.json").read_bytes())
        applications = {
            root / "AI_HLY/AI_HLY.entitlements",
            root / "HanlinMiniAppsApp/HanlinMiniApps.entitlements",
        }
        self.assertTrue(lock["node"]["buildConfiguration"]["pointerCompression"])
        for path in applications:
            with self.subTest(application=str(path)):
                self.assertIs(plistlib.loads(path.read_bytes()).get(EXTENDED_VA), True)
        shipping_entitlements = {root / target.entitlements for target in SIGNING_TARGETS}
        self.assertTrue(applications <= shipping_entitlements)
        # Keep the original top-level coverage and include every nested shipping extension.
        entitlement_paths = shipping_entitlements | set(root.glob("*/*.entitlements"))
        for path in sorted(entitlement_paths - applications):
            with self.subTest(extension=str(path)):
                self.assertNotIn(EXTENDED_VA, plistlib.loads(path.read_bytes()), str(path))

    def test_requested_entitlement_alone_is_not_signing_or_physical_acceptance(self):
        report = verify({"node": {"buildConfiguration": {"pointerCompression": True}}},
                        {EXTENDED_VA: True}, {"Entitlements": {EXTENDED_VA: True}})
        self.assertIsNone(report["signedExtendedVA"])
        self.assertFalse(report["physicalAllocationVerified"])

    def test_real_signed_entitlement_must_survive_the_embedded_profile_and_export(self):
        report = verify({"node": {"buildConfiguration": {"pointerCompression": True}}},
                        {EXTENDED_VA: True}, {"Entitlements": {EXTENDED_VA: True}}, {EXTENDED_VA: True})
        self.assertTrue(report["signedExtendedVA"])
        self.assertFalse(report["physicalAllocationVerified"])

    def test_missing_string_or_integer_values_cannot_masquerade_as_true(self):
        lock = {"node": {"buildConfiguration": {"pointerCompression": True}}}
        for value in (None, False, 1, "true"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "main app"):
                    verify(lock, {EXTENDED_VA: value}, {"Entitlements": {EXTENDED_VA: True}})
                with self.assertRaisesRegex(ValueError, "profile does not authorize"):
                    verify(lock, {EXTENDED_VA: True}, {"Entitlements": {EXTENDED_VA: value}})
                with self.assertRaisesRegex(ValueError, "signed main app"):
                    verify(lock, {EXTENDED_VA: True}, {"Entitlements": {EXTENDED_VA: True}}, {EXTENDED_VA: value})

    def test_an_explicit_request_requires_a_profile_even_without_compressed_pointers(self):
        with self.assertRaisesRegex(ValueError, "profile does not authorize"):
            verify({"node": {}}, {EXTENDED_VA: True}, {"Entitlements": {}})
        report = verify({"node": {}}, {}, {"Entitlements": {}})
        self.assertFalse(report["extendedVirtualAddressingRequired"])


if __name__ == "__main__":
    unittest.main()
