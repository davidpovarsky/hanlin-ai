"""Pure file-reader controls for Studio admission, never OS/runtime evidence."""
from pathlib import Path
import copy
import datetime
import io
import json
import shutil
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import observe_studio_gallery as studio


class StudioGalleryReaderControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / "data"
        self.app = self.root / "HanlinMiniApps.app"
        self.data.mkdir()
        self.app.mkdir()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        self.request = {"schema": 1, "runID": "12345678-1234-1234-1234-123456789abc",
                        "surface": "studioGallery", "exampleID": "nativescript-hello-world",
                        "engine": "nativescript", "marker": "שלום Studio 12345678",
                        "packageTitle": "Studio nativescript-hello-world 12345678",
                        "startedAt": now, "observedAt": now, "phase": "gallery-ready"}
        self.template = {
            "index.ts": b"const greeting = 'Hello from NativeScript!';\n",
            "script.json": self.json_bytes({"name": "NativeScript Hello World", "version": "1.0.0",
                "entry": "nativescript/app/bundle.mjs", "runInApp": True, "hanlinRuntime": "hanlin-nativescript"}),
            "hanlin.authoring.json": self.json_bytes({"schemaVersion": 1, "engine": "nativescript",
                "entry": "index.ts", "tsconfig": "tsconfig.json"}),
            "tsconfig.json": self.json_bytes({"include": ["index.ts"]}),
            "package.json": self.json_bytes({"name": "reader-control", "dependencies": {}}),
        }
        self.engine = {"toolingRoot": "nativescript", "tsconfigPath": "nativescript/tsconfig.json",
                       "typescriptPath": "nativescript/node_modules/typescript/lib/typescript.js",
                       "packageVersions": {"typescript": "5.9.3"},
                       "typescript": {"compilerVersion": "5.9.3"},
                       "typeCheckingPolicy": {"strictSource": True, "checkOriginalDeclarationBodies": False},
                       "examples": [{"id": self.request["exampleID"], "engine": "nativescript",
                                     "path": "examples/" + self.request["exampleID"], "entry": "index.ts"}]}
        self.manifest = {"schemaVersion": 1, "engines": {"nativescript": self.engine}}
        members = {"MiniAppSDK/nativescript/tsconfig.json": self.json_bytes({"compilerOptions": {
                       "strict": True, "skipLibCheck": True, "checkJs": False}}),
                   "MiniAppSDK/nativescript/node_modules/typescript/lib/typescript.js": b"module.exports = {version: '5.9.3'};\n",
                   "MiniAppSDK/nativescript/node_modules/typescript/lib/lib.esnext.d.ts": b"declare const original: unique symbol;\n"}
        members.update({"MiniAppSDK/examples/" + self.request["exampleID"] + "/" + name: raw
                        for name, raw in self.template.items()})
        self.manifest["files"] = [{"path": name[len("MiniAppSDK/"):], "sha256": studio.shared.digest(raw), "bytes": len(raw)}
                                  for name, raw in sorted(members.items())]
        members["MiniAppSDK/miniapp-sdk.json"] = self.json_bytes(self.manifest)
        self.write_zip(self.app / "RuntimeHostResources.zip", members)
        archive_hash = studio.shared.digest((self.app / "RuntimeHostResources.zip").read_bytes())
        self.host = self.data / studio.RUNTIME / "runtime/node" / ("host-" + archive_hash)
        self.host.mkdir(parents=True)
        (self.host / ".ready").write_text(archive_hash)
        for name, raw in members.items():
            path = self.host / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        self.roots = {"app": self.app, "data": self.data}
        self.workspace = self.data / studio.RUNTIME / "clients/tools/miniapp-studio"
        self.workspace.mkdir(parents=True)

    @staticmethod
    def json_bytes(value):
        return (json.dumps(value, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode()

    @staticmethod
    def write_zip(path, members):
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as archive:
            for name, raw in sorted(members.items()):
                archive.writestr(name, raw)

    def prepared_case(self, edit=False):
        sdk = studio.bind_sdk(self.roots, self.request)
        copies = [self.request["exampleID"] + suffix for suffix in ("-A1234567", "-B1234567")]
        for name in copies:
            shutil.copytree(Path(sdk["root"]) / sdk["example"]["path"], self.workspace / name)
        case = {"fixed": {key: self.request[key] for key in studio.FIXED}, "sdk": sdk,
                "workspace": self.workspace, "baselineProjects": set(), "baselineInstalledIDs": set(), "copies": copies}
        if edit:
            first = self.workspace / copies[0]
            (first / "index.ts").write_bytes(self.template["index.ts"].replace(
                b"Hello from NativeScript!", self.request["marker"].encode()))
            manifest = json.loads(self.template["script.json"])
            manifest["name"] = self.request["packageTitle"]
            (first / "script.json").write_bytes(self.json_bytes(manifest))
            case["editedHashes"] = studio.hashes(studio.verify_copies(case, self.roots, edited=True))
        return case

    def temporary_build(self, case):
        """Small consistent reader input, not a compiler or native receipt."""
        project = self.workspace / case["copies"][0]
        actual = studio.source_tree(project, self.data)
        stage = project / ".hanlin-build/abcdef12-1234-1234-1234-123456789abc"
        package = stage / "package"
        members = {"source/" + name: doc["raw"] for name, doc in actual.items()}
        members["script.json"] = actual["script.json"]["raw"]
        members["nativescript/app/bundle.mjs"] = b"export const readerControl = true;\n"
        sdk = {"packageVersions": self.engine["packageVersions"],
               "manifestSHA256": case["sdk"]["manifest"]["sha256"], "compilerVersion": "5.9.3"}
        author = {"schemaVersion": 1, "engine": "nativescript", "entry": "index.ts", "tsconfig": "tsconfig.json",
                  "sourceRoot": "source", "sourceHashes": studio.hashes(actual),
                  "compiledHashes": {name: studio.shared.digest(raw) for name, raw in members.items() if not name.startswith("source/")},
                  "sdk": sdk}
        report = {"schemaVersion": 1, "engine": "nativescript", "operation": "build", "succeeded": True,
                  "diagnostics": [], "sourceRoot": "source", "sdk": sdk,
                  "typecheck": {"strict": True, "checkJs": False, "skipLibCheck": True, "dependencyDeclarationsChecked": False}}
        members["hanlin.authoring.json"] = self.json_bytes(author)
        members["hanlin.validation.json"] = self.json_bytes(report)
        for name, raw in members.items():
            path = package / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        self.write_zip(stage / "MiniApp.hanlinNativeScript", members)
        return stage, members

    def replace_built_member(self, stage, members, name, raw):
        members[name] = raw
        (stage / "package" / name).write_bytes(raw)
        self.write_zip(stage / "MiniApp.hanlinNativeScript", members)

    def test_two_copies_preserve_shipped_bytes_and_allow_only_exact_first_edit(self):
        case = self.prepared_case(edit=True)
        actual = studio.verify_copies(case, self.roots, edited=True)
        self.assertEqual(studio.hashes(actual), case["editedHashes"])
        studio.verify_sdk_unchanged(case, self.roots, full=True)

    def test_unpacked_source_must_match_actual_bundled_source(self):
        path = self.host / "MiniAppSDK/examples" / self.request["exampleID"] / "index.ts"
        path.write_text("changed SDK source\n")
        with self.assertRaisesRegex(studio.shared.ObservationError, "app-bundled bytes"):
            studio.bind_sdk(self.roots, self.request)

    def test_unpack_stamp_cannot_name_another_bundle(self):
        (self.host / ".ready").write_text("0" * 64)
        with self.assertRaisesRegex(studio.shared.ObservationError, "unpack stamp"):
            studio.bind_sdk(self.roots, self.request)

    def test_mutated_compiler_cannot_keep_manifest_and_version_identity(self):
        path = self.host / "MiniAppSDK" / self.engine["typescriptPath"]
        path.write_bytes(b"module.exports = {version: '5.9.3', changedCompiler: true};\n")
        with self.assertRaisesRegex(studio.shared.ObservationError, "compiler/declaration/tooling bytes"):
            studio.bind_sdk(self.roots, self.request)

    def test_unlisted_tooling_file_cannot_enter_the_actual_compiler_closure(self):
        path = self.host / "MiniAppSDK/nativescript/node_modules/extra.js"
        path.write_text("module.exports = {};\n")
        with self.assertRaisesRegex(studio.shared.ObservationError, "compiler/tooling inventory"):
            studio.bind_sdk(self.roots, self.request)

    def test_report_policy_uses_actual_project_override(self):
        policy = studio.original_typecheck({"compilerOptions": {"strict": True, "skipLibCheck": True, "checkJs": False}},
                                          {"compilerOptions": {"skipLibCheck": False}, "include": ["index.ts"]})
        self.assertEqual(policy, {"strict": True, "checkJs": False, "skipLibCheck": False, "dependencyDeclarationsChecked": True})

    def test_editing_second_copy_is_rejected(self):
        case = self.prepared_case(edit=True)
        (self.workspace / case["copies"][1] / "index.ts").write_text("altered second project\n")
        with self.assertRaisesRegex(studio.shared.ObservationError, "independent second copy"):
            studio.verify_copies(case, self.roots, edited=True)

    def test_edit_cannot_change_original_runtime_logic_or_compiler_options(self):
        case = self.prepared_case(edit=True)
        path = self.workspace / case["copies"][0] / "tsconfig.json"
        path.write_bytes(self.json_bytes({"compilerOptions": {"strict": False}}))
        with self.assertRaisesRegex(studio.shared.ObservationError, "compiler configuration"):
            studio.verify_copies(case, self.roots, edited=True)

    def test_extra_manifest_mutation_is_rejected(self):
        case = self.prepared_case(edit=True)
        path = self.workspace / case["copies"][0] / "script.json"
        value = json.loads(path.read_bytes())
        value["runInApp"] = 1
        path.write_bytes(self.json_bytes(value))
        with self.assertRaisesRegex(studio.shared.ObservationError, "manifest fields"):
            studio.verify_copies(case, self.roots, edited=True)

    def test_project_link_cannot_substitute_shared_source(self):
        case = self.prepared_case(edit=True)
        path = self.workspace / case["copies"][1] / "index.ts"
        path.unlink()
        path.symlink_to(self.workspace / case["copies"][0] / "index.ts")
        with self.assertRaisesRegex(studio.shared.ObservationError, "symbolic link"):
            studio.verify_copies(case, self.roots, edited=True)

    def test_consistent_temporary_build_retains_original_engine_policy(self):
        case = self.prepared_case(edit=True)
        self.temporary_build(case)
        facts = studio.build_facts(case, self.roots)
        self.assertTrue(facts["validation"]["typecheck"]["skipLibCheck"])
        self.assertTrue(facts["validation"]["typecheck"]["strict"])
        self.assertEqual(facts["authoring"]["sourceHashes"], case["editedHashes"])

    def test_consistently_modified_zip_and_report_cannot_weaken_sdk_policy(self):
        case = self.prepared_case(edit=True)
        stage, members = self.temporary_build(case)
        report = json.loads(members["hanlin.validation.json"])
        report["typecheck"]["strict"] = False
        self.replace_built_member(stage, members, "hanlin.validation.json", self.json_bytes(report))
        with self.assertRaisesRegex(studio.shared.ObservationError, "exact compiler policy"):
            studio.build_facts(case, self.roots)

    def test_consistently_modified_retained_source_cannot_replace_ui_edit(self):
        case = self.prepared_case(edit=True)
        stage, members = self.temporary_build(case)
        changed = b"const greeting = 'unrelated';\n"
        self.replace_built_member(stage, members, "source/index.ts", changed)
        author = json.loads(members["hanlin.authoring.json"])
        author["sourceHashes"]["index.ts"] = studio.shared.digest(changed)
        self.replace_built_member(stage, members, "hanlin.authoring.json", self.json_bytes(author))
        with self.assertRaisesRegex(studio.shared.ObservationError, "edited source"):
            studio.build_facts(case, self.roots)

    def test_zip_must_equal_original_prepared_package(self):
        case = self.prepared_case(edit=True)
        stage, members = self.temporary_build(case)
        members["nativescript/app/bundle.mjs"] = b"different archive payload\n"
        self.write_zip(stage / "MiniApp.hanlinNativeScript", members)
        with self.assertRaisesRegex(studio.shared.ObservationError, "prepared package"):
            studio.build_facts(case, self.roots)

    def test_unprefixed_or_other_installed_entry_is_rejected(self):
        case = self.prepared_case(edit=True)
        self.temporary_build(case)
        case["build"] = studio.build_facts(case, self.roots)
        for entry_path in ("nativescript/app/bundle.mjs", "source/other.mjs"):
            with self.subTest(entry=entry_path):
                catalog = {"schemaVersion": 1, "revision": 1, "packages": {"reader-package": {
                    "enabled": True, "record": {"installedPackageID": "reader-package", "packageID": "reader",
                        "activeGeneration": 1, "sourceDigest": case["build"]["archive"]["sha256"]},
                    "entrypoints": [{"id": "app", "kind": "app", "compatibility": "supported",
                        "runtimeProfile": "hanlin-nativescript", "supportedContexts": ["mainApplication"],
                        "sourcePath": entry_path}]}}}
                path = self.data / studio.INSTALLED / "registry/catalog.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(self.json_bytes(catalog))
                with self.assertRaisesRegex(studio.shared.ObservationError, "foreground app entry"):
                    studio.installed_build(case, self.roots)

    def test_numeric_schema_and_wrong_fresh_marker_are_rejected(self):
        self.assertEqual(studio.validate_request(self.request), self.request["runID"])
        for field, value in (("schema", True), ("schema", 1.0), ("marker", "שלום Studio stale000")):
            request = copy.deepcopy(self.request)
            request[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(studio.shared.ObservationError):
                studio.validate_request(request)


if __name__ == "__main__":
    unittest.main()
