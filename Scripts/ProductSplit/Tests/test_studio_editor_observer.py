"""Portable negative controls for the actual Studio reader; no OS claims."""
from pathlib import Path
import base64
import copy
import datetime
import json
import plistlib
import shutil
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import observe_studio_editor as reader
import observe_studio_gallery as gallery
import observe_shortcut_surfaces as shared
from observe_share_translation_surfaces import raw_file


def instant(seconds):
    return datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).isoformat(timespec="milliseconds")

class EditorFixture:
    def __init__(self, root, scenario="files", engine="expo"):
        self.root = root
        self.data, self.app, self.group = [root / name for name in ("data", "app", "group")]
        self.evidence, self.exchange = root / "evidence/shortcut-observer", root / "runner/exchange"
        for path in (self.data, self.app, self.group, self.evidence, self.exchange, self.data / "Documents"):
            path.mkdir(parents=True, exist_ok=True)
        self.roots = {"data": self.data, "app": self.app, "group": self.group,
                      "extensions": self.group / "HanlinMiniApps/v1/ScriptingExtensions",
                      "configuration": {"StorageNamespace": "HanlinMiniApps/v1"}, "infoSHA256": "a" * 64}
        self.workspace = self.data / reader.RUNTIME / "clients/tools/miniapp-studio"
        self.workspace.mkdir(parents=True)
        self.run = "01234567-89ab-4cde-8fab-0123456789ab"
        example = "expo-hello-world" if engine == "expo" else "nativescript-hello-world"
        self.request = {"schema": 1, "runID": self.run, "surface": "studioEditor", "scenario": scenario,
                        "engine": engine, "exampleID": example, "marker": "שלום Editor 01234567",
                        "startedAt": instant(time.time() - 30), "processID": 321, "currentProcessID": 321}
        self.directory = self.exchange / self.run
        self.directory.mkdir()
        self.template_root = self.data / "sdk/examples" / example
        self.template_root.mkdir(parents=True)
        originals = {"index.ts": b"export const original = 1;\n", "App.tsx": b"export const title = 'Hello Expo';\n",
                     "script.json": b'{"id":"original"}\n', "hanlin.authoring.json": b'{"schemaVersion":1}\n',
                     "tsconfig.json": b'{"include":["**/*.ts"]}\n'}
        for path, value in originals.items(): (self.template_root / path).write_bytes(value)
        archive = self.app / "RuntimeHostResources.zip"
        archive.write_bytes(b"portable reader fixture; not a produced SDK archive")
        config = self.data / "sdk/config.json"; config.write_text('{}\n')
        ready = self.data / "sdk/.ready"; ready.write_text("ready")
        manifest = self.data / "sdk/manifest.json"; manifest.write_text('{}\n')
        self.sdk = {"archive": reader.document_bytes(raw_file(archive, self.app)), "root": str(self.data / "sdk"),
                    "template": gallery.source_tree(self.template_root, self.data),
                    "config": shared.read_document(config, self.data), "manifest": shared.read_document(manifest, self.data),
                    "ready": reader.document_bytes(raw_file(ready, self.data)), "descriptor": {},
                    "example": {"id": example, "path": "examples/" + example}, "tooling": {}, "effectiveTypecheck": {}}
        self.args = types.SimpleNamespace(device="owned", bundle_id="com.itorah.hanlinminiapps", studio_inputs=None)
        self.seen = {}
        self.tick = time.time() - 20
        self.project = example + "-ABCDEF12"

    def snapshot(self):
        return {str(p.relative_to(self.data)): p.read_bytes() for p in self.data.rglob("*") if p.is_file()}

    def screen(self, label, pid=321, *needles):
        # Only a portable reader fixture. Native UI must supply its own real screenshots.
        (self.directory / (label + ".png")).write_bytes(base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZQAAAABJRU5ErkJggg=="))
        (self.directory / (label + "-accessibility.txt")).write_text(
            "Attributes: Application, 0x123, pid: " + str(pid) + ", label: 'Hanlin MiniApps'\n" + "\n".join(needles))

    def phase(self, phase, **fields):
        self.tick += 0.1
        self.request.update(fields, phase=phase, observedAt=instant(self.tick))
        self.screen("studio-editor-phase-" + phase, self.request["currentProcessID"], "miniapps-gallery-" + self.request["exampleID"])
        before = self.snapshot()
        with mock.patch.object(shared, "product_roots", return_value=self.roots), \
             mock.patch.object(gallery, "bind_sdk", return_value=self.sdk), \
             mock.patch.object(gallery, "verify_sdk_unchanged"):
            reader.observe_case(self.args, self.request, self.directory, self.evidence, self.seen)
        if before != self.snapshot(): raise AssertionError("The reader wrote into production storage")
        return self.seen[self.run]

    def prepare(self):
        self.phase("gallery-ready", galleryLoaded=True)
        shutil.copytree(self.template_root, self.workspace / self.project)
        self.phase("copy-ready", copyObserved=True)

    def write(self, relative, raw):
        path = self.workspace / self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)

    def windows(self, left="original", right="original"):
        self.request["windowingScreenFrame"] = [0.0, 0.0, 1024.0, 768.0]
        self.request["editorWindowCount"] = 2
        self.request["editorWindows"] = [
            {"side": "left", "windowFrame": [0.0, 0.0, 512.0, 768.0], "editorFrame": [10.0, 100.0, 492.0, 400.0],
             "text": reader.text_for(self.request, left)},
            {"side": "right", "windowFrame": [512.0, 0.0, 512.0, 768.0], "editorFrame": [522.0, 100.0, 492.0, 400.0],
             "text": reader.text_for(self.request, right)}]

    def journal(self, original, edited):
        path = self.data / reader.RUNTIME / "clients/tools/miniapp-studio-drafts/ABCD0123-4567-489A-BCDE-0123456789AB.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        value = {"id": path.stem, "projectPath": str(self.workspace / self.project),
                 "path": reader.paths(self.request)["conflict"], "text": reader.text_for(self.request, edited),
                 "original": base64.b64encode(reader.text_for(self.request, original).encode()).decode(),
                 "savedAt": time.time() - 978307200}
        path.write_text(json.dumps(value))
        return path

    def files_before_reopen(self):
        self.prepare(); wanted = reader.paths(self.request)
        self.write(wanted["created"], reader.text_for(self.request, "created").encode())
        self.phase("file-created", createdPath=wanted["created"], fileCreateObserved=True)
        (self.workspace / self.project / wanted["created"]).unlink()
        self.write(wanted["moved"], reader.text_for(self.request, "after move").encode())
        self.phase("file-moved", movedPath=wanted["moved"], fileMoveObserved=True)
        (self.workspace / wanted["folder"]).mkdir(parents=True)
        self.phase("folders-created", folderCreateObserved=True)
        self.write(".miniapps-folder.json", json.dumps(reader.STYLE).encode())
        self.phase("style-saved", styleSaveObserved=True)
        destination = wanted["folder"] + "/" + self.project
        (self.workspace / self.project).rename(self.workspace / destination)
        self.phase("project-moved", projectMoveObserved=True, movedProject=destination)
        self.screen("studio-editor-reopened", 987, self.request["marker"], "miniapps-studio-editor")
        self.screen("studio-editor-reopened-appearance", 987, "Folder appearance", "star.fill", "Purple")
        return dict(currentProcessID=987, reopenedProcessID=987, reopenedSourceObserved=True,
                    reopenedSymbolObserved="star.fill", reopenedColorObserved="purple")


class StudioEditorObserverTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def fixture(self, scenario="files", engine="expo"):
        return EditorFixture(self.root, scenario, engine)

    def test_strict_request_identity_types_and_phase(self):
        f = self.fixture(); f.request.update(phase="gallery-ready", observedAt=instant(time.time()))
        reader.validate_request(f.request)
        for key, value in (("schema", True), ("currentProcessID", True), ("processID", 0),
                           ("marker", "foreign"), ("exampleID", "other"), ("scenario", "all"), ("phase", "finished")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                reader.validate_request({**f.request, key: value})

    def test_original_source_inventory_rejects_extra_or_changed_files(self):
        f = self.fixture(); f.prepare(); case = f.seen[f.run]
        reader.project_snapshot(case, f.roots)
        f.write("unexpected.ts", b"extra")
        with self.assertRaises(ValueError): reader.project_snapshot(case, f.roots)
        (f.workspace / f.project / "unexpected.ts").unlink()
        f.write("index.ts", b"changed original")
        with self.assertRaises(ValueError): reader.project_snapshot(case, f.roots)

    def test_window_observation_requires_two_real_nonoverlapping_editors(self):
        f = self.fixture("conflict", "nativescript"); f.windows()
        expected = [reader.text_for(f.request, "original")] * 2
        admitted = {"windows": reader.window_observations(f.request, expected), "screenFrame": f.request["windowingScreenFrame"]}
        for mutation in ("address-token", "overlap", "wrong-text", "changed-owner", "bool-count", "outside-screen"):
            request = copy.deepcopy(f.request)
            if mutation == "address-token": request["editorWindows"][1]["token"] = "0x123"
            if mutation == "overlap": request["editorWindows"][1] = copy.deepcopy(request["editorWindows"][0]); request["editorWindows"][1]["side"] = "right"
            if mutation == "wrong-text": request["editorWindows"][1]["text"] = "new owner"
            if mutation == "changed-owner": request["editorWindows"][1]["windowFrame"][0] += 20
            if mutation == "bool-count": request["editorWindowCount"] = True
            if mutation == "outside-screen": request["windowingScreenFrame"][2] = 800
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                reader.window_observations(request, expected, admitted)
        request = copy.deepcopy(f.request)
        for window in request["editorWindows"]:
            window["windowFrame"][3] = 600; window["editorFrame"][3] = 300
        reader.window_observations(request, expected, admitted)  # keyboard height does not invent a new identity

    def test_fresh_log_event_must_bind_current_container_and_time(self):
        f = self.fixture("assistance"); path = f.data / reader.RUNTIME / "logs/node-runtime.log"
        path.parent.mkdir(parents=True)
        root = f.data / reader.RUNTIME
        event = {"timestamp": instant(time.time()), "event": "runtime_paths_configured",
                 "fields": {"home": str(root / "runtime/home"), "npmCache": str(root / "cache/npm"),
                            "npmPrefix": str(root / "runtime/npm-prefix"), "npmTemp": str(root / "staging/tmp")}}
        path.write_text(json.dumps(event) + "\n")
        reader.actual_log({"fixed": f.request}, f.roots)
        for mutation in ("old", "future", "foreign", "no-zone"):
            changed = copy.deepcopy(event)
            if mutation == "old": changed["timestamp"] = instant(time.time() - 3600)
            if mutation == "future": changed["timestamp"] = instant(time.time() + 60)
            if mutation == "foreign": changed["fields"]["home"] = "/another/product"
            if mutation == "no-zone": changed["timestamp"] = "2026-11-27T09:00:00"
            path.write_text(json.dumps(changed) + "\n")
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): reader.actual_log({"fixed": f.request}, f.roots)

    def test_persisted_preferences_reject_bool_and_wrong_real_font(self):
        f = self.fixture("assistance"); p = f.data / "Library/Preferences/com.itorah.hanlinminiapps.plist"; p.parent.mkdir(parents=True)
        values = {"miniapps.studio.fontName": reader.FONT, "miniapps.studio.fontSize": 22.0, "miniapps.studio.theme": "dark"}
        p.write_bytes(plistlib.dumps(values)); reader.preferences(f.roots, f.args.bundle_id)
        for key, value in (("fontSize", True), ("fontSize", 15), ("fontName", "Menlo-Regular"), ("theme", "system")):
            p.write_bytes(plistlib.dumps({**values, "miniapps.studio." + key: value}))
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): reader.preferences(f.roots, f.args.bundle_id)

    def test_conflict_journal_requires_real_stale_original_and_unique_current_draft(self):
        f = self.fixture("conflict", "nativescript"); f.prepare(); path = f.journal("original", "writer B draft")
        case = f.seen[f.run]; reader.conflict_draft(case, f.roots, "original", "writer B draft")
        original = json.loads(path.read_text())
        for mutation in ("original", "text", "old-date", "wrong-project"):
            value = copy.deepcopy(original)
            if mutation == "original": value["original"] = base64.b64encode(b"winning replacement").decode()
            if mutation == "text": value["text"] = "unrelated"
            if mutation == "old-date": value["savedAt"] -= 3600
            if mutation == "wrong-project": value["projectPath"] += "/sibling"
            path.write_text(json.dumps(value))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): reader.conflict_draft(case, f.roots, "original", "writer B draft")

    def test_fresh_inputs_and_export_cannot_overwrite_preexisting_paths(self):
        f = self.fixture(); (f.data / "Documents" / reader.paths(f.request)["export"]).write_text("user data")
        with self.assertRaises(ValueError): f.phase("gallery-ready", galleryLoaded=True)
        self.assertFalse((f.directory / "identity.json").exists())
        self.assertEqual((f.data / "Documents" / reader.paths(f.request)["export"]).read_text(), "user data")

    def test_phase_order_and_frozen_preparation_reject_substitution(self):
        f = self.fixture(); f.prepare()
        with self.assertRaises(ValueError): f.phase("style-saved", styleSaveObserved=True)
        f.request["scenario"] = "assistance"
        with self.assertRaises(ValueError): f.phase("assistance-observed")
        self.assertFalse((f.directory / "completion.json").exists())

    def test_ordered_phases_accept_original_whole_second_timestamps_but_reject_regression(self):
        f = self.fixture(); f.prepare(); case = f.seen[f.run]
        path = reader.paths(f.request)["created"]
        f.write(path, reader.text_for(f.request, "created").encode())
        # The actual preserved UI checkpoint helper can emit the same second.
        f.tick -= 0.1
        f.phase("file-created", createdPath=path, fileCreateObserved=True)
        self.assertEqual(case["done"][-1], "file-created")
        f.request.update(phase="file-moved", observedAt=instant(f.tick - 1))
        with mock.patch.object(shared, "product_roots", return_value=f.roots), \
             mock.patch.object(gallery, "verify_sdk_unchanged"), self.assertRaises(ValueError):
            reader.observe_case(f.args, f.request, f.directory, f.evidence, f.seen)
        self.assertFalse((f.directory / "editor-file-moved.json").exists())

    def test_local_files_flow_reads_only_actual_ui_results_and_reopens_styles(self):
        f = self.fixture(); fields = f.files_before_reopen()
        f.phase("reopened", **fields)
        self.assertTrue(f.seen[f.run]["finished"])
        self.assertEqual(json.loads((f.directory / "completion.json").read_text())["iCloudAccountAndRemoteConflict"], "NOT_RUN")

    def test_screenshot_wrong_process_or_missing_actual_controls_is_rejected(self):
        f = self.fixture(); f.screen("studio-editor-reopened", 999, "miniapps-studio-editor")
        with self.assertRaises(ValueError): reader.screen(f.directory, "studio-editor-reopened", 321, ("miniapps-studio-editor",))
        with self.assertRaises(ValueError): reader.screen(f.directory, "studio-editor-reopened", 999, ("Save a copy",))

    def test_final_pid_cannot_reuse_original_process(self):
        f = self.fixture("import"); f.prepare = lambda: None
        # A minimal last-phase case isolates the actual final admission boundary.
        f.request.update(phase="reopened", observedAt=instant(time.time()), currentProcessID=321)
        f.seen[f.run] = {"kind": "studioEditor", "fixed": {key: f.request[key] for key in reader.FIXED},
            "directory": str(f.directory), "done": list(reader.STEPS["import"][:-1]), "finished": False,
            "roots": f.roots, "sdk": f.sdk, "workspace": f.workspace, "project": f.project, "output": f.evidence / f.run}
        with self.assertRaises(ValueError): reader.observe_case(f.args, f.request, f.directory, f.evidence, f.seen)
        self.assertFalse((f.directory / "completion.json").exists())

    def test_final_product_configuration_is_reread_before_terminal_write(self):
        f = self.fixture(); fields = f.files_before_reopen()
        f.request.update(fields, phase="reopened", observedAt=instant(time.time()))
        f.screen("studio-editor-phase-reopened", 987)
        changed = {**f.roots, "infoSHA256": "b" * 64}
        with mock.patch.object(shared, "product_roots", side_effect=[f.roots, changed]), \
             mock.patch.object(gallery, "verify_sdk_unchanged") as sdk_check, self.assertRaises(ValueError):
            reader.observe_case(f.args, f.request, f.directory, f.evidence, f.seen)
        self.assertTrue(any(call.kwargs.get("full") is True for call in sdk_check.call_args_list))
        self.assertFalse((f.directory / "completion.json").exists())

    def test_reopened_style_and_move_cannot_be_inferred_only_from_disk(self):
        f = self.fixture(); fields = f.files_before_reopen()
        with self.assertRaises(ValueError): f.phase("reopened", **{**fields, "reopenedSymbolObserved": "folder"})
        shutil.copytree(f.template_root, f.workspace / f.project)
        with self.assertRaises(ValueError): f.phase("reopened", **fields)
        self.assertFalse((f.directory / "completion.json").exists())

    def test_font_ui_requires_integer_choice_even_when_plist_is_real_double(self):
        f = self.fixture("assistance"); f.prepare(); case = f.seen[f.run]
        path = reader.paths(f.request)["assistance"]
        f.write(path, reader.assistance_source(f.request).encode())
        case["done"].append("assistance-observed")  # isolate this phase, not a full-flow claim
        fields = {"fontPickerObserved": True, "fontFamilySelected": "Courier New", "fontFaceSelected": "Regular",
                  "fontSizeSelected": 22.0, "themeSelected": "dark"}
        with self.assertRaises(ValueError): f.phase("preferences-saved", **fields)
        self.assertFalse((f.directory / "editor-preferences-saved.json").exists())

    def test_two_writer_journal_reload_recovery_and_separate_copy_protocol(self):
        f = self.fixture("conflict", "nativescript"); f.prepare()
        path = reader.paths(f.request)["conflict"]
        f.write(path, reader.text_for(f.request, "original").encode())
        f.phase("document-ready", documentCreateObserved=True)
        f.windows()
        f.request.update(windowingEnabledObserved=True, newWindowCreatedObserved=True,
                         windowingSettingsProcessID=500, windowingSystemProcessID=600)
        f.screen("studio-editor-windowing-settings", 500, "Windowed Apps")
        f.screen("studio-editor-new-window-menu", 600, "New Window", "Hanlin MiniApps")
        f.screen("studio-editor-two-windows", 321, "miniapps-studio-editor'", "miniapps-studio-editor'", f.request["marker"])
        f.phase("two-editors-ready")
        for index in range(2):
            winner, old, edited = ("writer A", "original", "writer B draft") if index == 0 else ("writer A again", "writer A", "writer B recovered")
            f.write(path, reader.text_for(f.request, winner).encode())
            f.windows(winner, old)
            f.phase("first-save" if index == 0 else "second-save", writerAObserved=reader.text_for(f.request, winner),
                    staleWriterBObserved=reader.text_for(f.request, old))
            journal = f.journal(old, edited)
            f.windows(winner, edited)
            phase = "conflict-visible" if index == 0 else "second-conflict"
            f.screen("studio-editor-" + phase, 321, "Your draft is preserved", "Reload file", "Save a copy")
            f.phase(phase, conflictObserved=True, draftTextObserved=reader.text_for(f.request, edited))
            if index == 0:
                journal.unlink()
                f.phase("reload-observed", reloadPressed=True, reloadedText=reader.text_for(f.request, winner))
        with self.assertRaises(ValueError): f.phase("recovered-draft", recoveredDraftOpened=True)
        f.screen("studio-editor-recovery-list", 999, "Recovered drafts", path)
        f.screen("studio-editor-recovered-conflict", 999, "Your draft is preserved", "Save a copy", f.request["marker"])
        f.phase("recovered-draft", currentProcessID=999, recoveredDraftOpened=True)
        copied = path[:-3] + "-copy-ABCDEF99.ts"
        f.write(copied, reader.text_for(f.request, "writer B recovered").encode()); journal.unlink()
        f.phase("copy-saved", saveCopyPressed=True)
        f.screen("studio-editor-reopened", 987, f.request["marker"], "miniapps-studio-editor")
        f.phase("reopened", currentProcessID=987, reopenedProcessID=987, reopenedSourceObserved=True,
                winningTextObserved=reader.text_for(f.request, "writer A again"),
                copyTextObserved=reader.text_for(f.request, "writer B recovered"), conflictCopyPath=copied)
        self.assertTrue(f.seen[f.run]["finished"])
        self.assertEqual((f.workspace / f.project / path).read_text(), reader.text_for(f.request, "writer A again"))


if __name__ == "__main__":
    unittest.main()
