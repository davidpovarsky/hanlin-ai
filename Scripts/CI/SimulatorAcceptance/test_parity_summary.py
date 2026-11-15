"""Synthetic reporting regression: process failure does not erase executed cases."""
from pathlib import Path
import tempfile
import unittest

import gate
import verify_parity


class ParitySummaryTests(unittest.TestCase):
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
