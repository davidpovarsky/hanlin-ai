from __future__ import annotations

import unittest

from Scripts.Runtime.validate_runtime_host_source_exclusion import validate_project

TARGET = "D7B6C3C02D50A55D004E3AD6"
GROUP = "D7B6C3C32D50A55D004E3AD6"
EXCEPTION = "A10000000000000000000030"
NODE_MODULES = "Downstream/RuntimeCore/Node/Host/node_modules"


def project(members: str, *, target: str = TARGET, registered: bool = True) -> str:
    return """
    {
        objects = {
            %s = {
                isa = PBXNativeTarget;
                name = AI_Hanlin;
                fileSystemSynchronizedGroups = (%s);
            };
            %s = {
                isa = PBXFileSystemSynchronizedRootGroup;
                path = AI_HLY;
                exceptions = (%s);
            };
            %s = {
                isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
                target = %s;
                membershipExceptions = (%s);
            };
        };
    }
    """ % (TARGET, GROUP if registered else "", GROUP, EXCEPTION, EXCEPTION, target, members)


class RuntimeHostSourceExclusionTests(unittest.TestCase):
    def test_original_and_normalized_project_spelling_and_whole_host_exclusion(self) -> None:
        for member in (NODE_MODULES + ",", '"' + NODE_MODULES + '" ,',
                       '"Downstream/RuntimeCore/Node/Host",'):
            with self.subTest(member=member):
                result = validate_project(project(member))
                self.assertEqual(result["target"], TARGET)
                self.assertEqual(result["excludedNodeModules"], NODE_MODULES)

    def test_another_targets_exclusion_is_not_evidence(self) -> None:
        with self.assertRaisesRegex(ValueError, "another target or comment"):
            validate_project(project('"' + NODE_MODULES + '",', target="OTHER_TARGET"))

    def test_unregistered_group_does_not_exclude_app_sources(self) -> None:
        with self.assertRaisesRegex(ValueError, "actual synchronized"):
            validate_project(project('"' + NODE_MODULES + '",', registered=False))

    def test_comment_sibling_and_descendant_do_not_hide_included_sources(self) -> None:
        misleading_comment = "\n/* " + NODE_MODULES + ", */\n"
        for member in ("", '"' + NODE_MODULES + '-old",', '"' + NODE_MODULES + '/only-one",'):
            with self.subTest(member=member):
                with self.assertRaisesRegex(ValueError, "another target or comment"):
                    validate_project(project(member) + misleading_comment)


if __name__ == "__main__":
    unittest.main()
