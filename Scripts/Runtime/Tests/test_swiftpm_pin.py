import importlib.util,json,pathlib,tempfile,unittest
spec=importlib.util.spec_from_file_location("pin",pathlib.Path(__file__).parents[1]/"verify-swiftpm-pin.py")
pin=importlib.util.module_from_spec(spec);spec.loader.exec_module(pin)
SHA="a"*40
class PinTests(unittest.TestCase):
 def fixture(self,root):
  (root/"Package.swift").write_text('.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")')
  (root/"Package.resolved").write_text(json.dumps({"pins":[{"identity":"yams","location":"https://github.com/jpsim/Yams.git","state":{"version":"6.2.2","revision":SHA}}]}))
 def test_exact_original_pin(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.fixture(root);self.assertEqual(pin.verify_pin(root,"6.2.2","jpsim/Yams",SHA)["revision"],SHA)
 def test_revision_only_is_not_tag_update_support(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.fixture(root);(root/"Package.swift").write_text('.package(url: "https://github.com/jpsim/Yams.git", revision: "'+SHA+'")')
   with self.assertRaisesRegex(ValueError,"Exact"):pin.verify_pin(root,"6.2.2","jpsim/Yams",SHA)
 def test_wrong_resolved_commit(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.fixture(root)
   with self.assertRaisesRegex(ValueError,"Resolved"):pin.verify_pin(root,"6.2.2","jpsim/Yams","b"*40)
 def test_wrong_source(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.fixture(root);p=root/"Package.resolved";d=json.loads(p.read_text());d["pins"][0]["location"]="https://example.com/Yams.git";p.write_text(json.dumps(d))
   with self.assertRaisesRegex(ValueError,"Resolved"):pin.verify_pin(root,"6.2.2","jpsim/Yams",SHA)
 def test_annotated_tag_peels_to_actual_commit(self):
  self.assertEqual(pin.peel({"type":"tag","sha":"b"*40},lambda sha:{"object":{"type":"commit","sha":SHA}}),SHA)
 def test_cyclic_tags_fail(self):
  with self.assertRaisesRegex(ValueError,"cyclic"):pin.peel({"type":"tag","sha":"b"*40},lambda sha:{"object":{"type":"tag","sha":sha}})
if __name__=="__main__":unittest.main()
