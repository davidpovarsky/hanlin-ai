import io,json,pathlib,subprocess,sys,unittest,warnings,zipfile
SCRIPT=pathlib.Path(__file__).parents[1]/"verify-upstream-proof.py"
class ProofReaderTests(unittest.TestCase):
 def run_bundle(self,entries):
  data=io.BytesIO()
  with warnings.catch_warnings():
   warnings.simplefilter("ignore")
   with zipfile.ZipFile(data,"w",compression=zipfile.ZIP_DEFLATED) as z:
    for name,body in entries:z.writestr(name,body)
  return subprocess.run([sys.executable,str(SCRIPT)],input=data.getvalue(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 def test_schema2_reads_known_bounded_logs_and_capture(self):
  r=self.run_bundle([("candidate-receipt.json",'{"schemaVersion":2}'),("host.log","reuse"),("host-context.json",'{"schemaVersion":1}')])
  self.assertEqual(r.returncode,0);d=json.loads(r.stdout);self.assertEqual(d["hostEntries"][1]["capture"]["schemaVersion"],1)
 def test_legacy_receipt_is_preserved_for_audit_without_synthetic_context(self):
  r=self.run_bundle([("candidate-receipt.json",'{"schemaVersion":1,"status":"EXECUTED_PASS"}'),("native-origin.log","original")])
  self.assertEqual(r.returncode,0);d=json.loads(r.stdout);self.assertIsNone(d["hostEntries"][0]["capture"])
 def test_duplicate_receipt_rejected(self):
  self.assertNotEqual(self.run_bundle([("candidate-receipt.json",'{"schemaVersion":2}')]*2).returncode,0)
 def test_duplicate_log_rejected(self):
  self.assertNotEqual(self.run_bundle([("candidate-receipt.json",'{"schemaVersion":2}'),("host.log","a"),("host.log","b")]).returncode,0)
 def test_oversized_log_rejected(self):
  self.assertNotEqual(self.run_bundle([("candidate-receipt.json",'{"schemaVersion":2}'),("host.log","x"*262145)]).returncode,0)
 def test_malformed_capture_rejected(self):
  self.assertNotEqual(self.run_bundle([("candidate-receipt.json",'{"schemaVersion":2}'),("host-context.json","bad-json")]).returncode,0)
 def test_unknown_schema_rejected(self):
  self.assertNotEqual(self.run_bundle([("candidate-receipt.json",'{"schemaVersion":99}')]).returncode,0)
if __name__=="__main__":unittest.main()
