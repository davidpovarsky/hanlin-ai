"""Synthetic reporting regression: process failure does not erase executed cases."""
from pathlib import Path
import json
import tempfile
import unittest

import gate
import verify_parity
from record_parity_output import case_end


class ParitySummaryTests(unittest.TestCase):
    def test_continuation_counts_only_two_current_cases(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-parity-summary-") as directory:
            root=Path(directory);folder=root/'iPad-he'
            gate.write(folder/'tests.json',{'devices':[{'osVersion':'27.0','modelName':'iPad Synthetic'}],'testNodes':[{'nodeType':'Test Case','nodeIdentifier':name+'()','result':'Passed'} for name in sorted(verify_parity.EXPECTED)]})
            gate.write(folder/'context.json',{'family':'iPad','locale':'he','xcodebuild_exit_code':0})
            (folder/'screenshots').mkdir();(folder/'screenshots/test.png').write_bytes(b'synthetic fixture')
            (folder/'Tests.xcresult').mkdir();(folder/'Tests.xcresult/Info.plist').write_bytes(b'synthetic fixture')
            result=verify_parity.summarize(root,'iPad-he')
            self.assertEqual(result['status'],'PASS')
            self.assertEqual(result['counts']['EXECUTED_PASS'],2)
            self.assertEqual(result['counts']['REUSED_VERIFIED_PASS'],0)
            self.assertEqual(verify_parity.summarize(root)['counts']['NOT_RUN'],6)

    def test_interrupted_end_lines_do_not_forge_complete_proof(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-parity-summary-") as directory:
            root=Path(directory);folder=root/'iPad-he';folder.mkdir()
            names=sorted(verify_parity.EXPECTED)
            (folder/'case-end-lines.jsonl').write_text('\n'.join(json.dumps({'selector':name,'result':status}) for name,status in zip(names,['failed','passed'])))
            result=verify_parity.summarize(root,'iPad-he')
            self.assertEqual(result['counts']['FAILED'],1)
            self.assertEqual(result['counts']['BLOCKED'],1)
            self.assertEqual(result['counts']['EXECUTED_PASS'],0)

    def test_only_native_case_end_lines_are_recorded(self):
        line="Test Case '-[HanlinParityUITests.ParityUITests testReloadReplacesOnlyUnsavedDraft]' passed (1.000 seconds)."
        self.assertEqual(case_end(line)['selector'],'ParityUITests/testReloadReplacesOnlyUnsavedDraft')
        self.assertIsNone(case_end("Test Suite 'ParityUITests' passed"))

    def test_observed_failure_is_not_misreported_as_not_run(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-parity-summary-") as directory:
            root=Path(directory);folder=root/'iPhone-en';names=sorted(verify_parity.EXPECTED)
            gate.write(folder/'tests.json',{'devices':[{'osVersion':'27.0','modelName':'iPhone Synthetic'}],'testNodes':[{'nodeType':'Test Case','nodeIdentifier':names[0]+'()','result':'Failed'},{'nodeType':'Test Case','nodeIdentifier':names[1]+'()','result':'Passed'}]})
            gate.write(folder/'context.json',{'family':'iPhone','locale':'en','xcodebuild_exit_code':65})
            (folder/'screenshots').mkdir();(folder/'screenshots/test.png').write_bytes(b'synthetic fixture')
            (folder/'Tests.xcresult').mkdir();(folder/'Tests.xcresult/Info.plist').write_bytes(b'synthetic fixture')
            result=verify_parity.summarize(root)
            self.assertEqual(result['counts']['FAILED'],1)
            self.assertEqual(result['counts']['EXECUTED_PASS'],1)
            self.assertEqual(result['counts']['NOT_RUN'],6)
            self.assertFalse(result['full_app_acceptance'])
            self.assertEqual(result['status'],'BLOCKED')


if __name__=='__main__':unittest.main()
