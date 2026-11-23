"""Focused selection tests; synthetic group names are not signing evidence."""
import importlib.util
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "Scripts/ProductSplit"))
from cross_app_owner_provisioning import _resolve_native_groups


class OwnerNativeGroupSelectionTests(unittest.TestCase):
    def setUp(self):
        self.plan = {"native_storage_families": {"anytype_owner": {
            "preferred_existing_groups": ["group.io.anytype.app.OWNER", "group.io.anytype.app"],
            "new_group_if_no_existing_grants": "group.io.anytype.app.OWNER"}}}
        self.product = {"native_storage_family": "anytype_owner"}

    def test_existing_profile_group_wins_and_is_not_claimed_new(self):
        snapshots = [(self.product, {"app_groups": ["group.io.anytype.app.OWNER", "group.com.itorah.shared"]}),
                     (self.product, {"app_groups": ["group.io.anytype.app.OWNER"]})]
        result = _resolve_native_groups(self.plan, snapshots)["anytype_owner"]
        self.assertEqual(result["group"], "group.io.anytype.app.OWNER")
        self.assertEqual(result["source"], "EXISTING_APPLE_PROFILE_GRANT")

    def test_empty_grants_explicitly_request_new_owner_private_group(self):
        result = _resolve_native_groups(self.plan, [(self.product, {"app_groups": []})])["anytype_owner"]
        self.assertEqual(result["group"], "group.io.anytype.app.OWNER")
        self.assertEqual(result["source"], "NEW_OWNER_PRIVATE_GROUP_REQUESTED")
        self.assertEqual(result["observed_groups"], [])

    def test_unmapped_multiple_existing_groups_do_not_silently_move_storage(self):
        with self.assertRaises(ValueError):
            _resolve_native_groups(self.plan, [(self.product, {"app_groups": ["group.legacy.one", "group.legacy.two"]})])


if __name__ == "__main__":
    unittest.main()
