"""Focused exporter integrity tests; fixture bytes are never native acceptance evidence."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "native_artifacts.py"
spec = importlib.util.spec_from_file_location("native_artifacts", SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeArtifactsTests(unittest.TestCase):
    def test_archive_roundtrip_preserves_bytes_permissions_and_internal_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Native.xcframework"
            source.mkdir()
            binary = source / "binary"
            binary.write_bytes(b"archive-integrity-fixture")
            binary.chmod(0o755)
            (source / "current").symlink_to("binary")
            first, second = root / "first.zip", root / "second.zip"
            native.archive_paths(first, [(source, native.PurePosixPath(source.name))])
            os.utime(binary, (1_700_000_000, 1_700_000_000))
            native.archive_paths(second, [(source, native.PurePosixPath(source.name))])
            self.assertEqual(native.digest(first), native.digest(second))
            output = root / "installed"
            output.mkdir()
            native.extract_verified(first, native.digest(first), output, source.name)
            self.assertEqual((output / source.name / "current").read_bytes(), binary.read_bytes())
            self.assertTrue((output / source.name / "current").is_symlink())
            self.assertTrue((output / source.name / "binary").stat().st_mode & stat.S_IXUSR)

    def test_corrupt_checksum_stops_before_installing_any_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "artifact.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("Native.xcframework/Info.plist", b"data")
            output = root / "installed"
            output.mkdir()
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                native.extract_verified(archive, "0" * 64, output, "Native.xcframework")
            self.assertEqual(list(output.iterdir()), [])

    def test_archive_paths_and_symlinks_cannot_escape_installation(self):
        cases = [
            [("../outside", b"bad", False)],
            [("Native.xcframework/../outside", b"bad", False)],
            [("Native.xcframework/link", b"../../outside", True)],
            [("Native.xcframework/link", b"target", True),
             ("Native.xcframework/link/child", b"bad", False)],
        ]
        for members in cases:
            with self.subTest(members=members), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / "bad.zip"
                with zipfile.ZipFile(archive, "w") as stream:
                    for name, data, symlink in members:
                        info = zipfile.ZipInfo(name)
                        info.create_system = 3
                        info.external_attr = ((stat.S_IFLNK | 0o777) if symlink else (stat.S_IFREG | 0o644)) << 16
                        stream.writestr(info, data)
                with zipfile.ZipFile(archive) as stream:
                    with self.assertRaises(ValueError):
                        native.archive_members(stream, "Native.xcframework")

    def test_missing_or_non_native_slices_are_not_publishable(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "NodeMobile.xcframework"
            source.mkdir()
            libraries = []
            for variant in ("device", "simulator"):
                identifier = "ios-arm64" + ("-simulator" if variant == "simulator" else "")
                libraries.append({"LibraryIdentifier": identifier, "LibraryPath": "libNodeMobile.a",
                                  "SupportedPlatform": "ios", "SupportedArchitectures": ["arm64"],
                                  **({"SupportedPlatformVariant": "simulator"} if variant == "simulator" else {})})
                (source / identifier).mkdir()
            (source / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))
            with self.assertRaisesRegex(ValueError, "Missing prepared library"):
                native.framework_libraries(source, "NodeMobile")
            for item in libraries:
                (source / item["LibraryIdentifier"] / item["LibraryPath"]).write_text("not a real native binary")
            with self.assertRaisesRegex(ValueError, "Not a native"):
                native.framework_libraries(source, "NodeMobile")

    def test_selected_install_does_not_download_unrelated_runtime_or_host_support(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / "sdk"
            sdk.mkdir()
            records = []
            archives = {}
            for name, member, kind in [
                ("NodeMobile", "NodeMobile.xcframework/fixture", "xcframework"),
                ("HanlinNodeHostSupport", "HanlinNodeHostSupport/AI_HLY/RuntimeHostResources.zip", "host-support"),
            ]:
                path = root / f"{name}.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr(member, b"download-selection-fixture")
                item = {"target": name, "kind": kind, "checksum": native.digest(path),
                        "root": "NodeMobile.xcframework" if kind == "xcframework" else name}
                if kind == "xcframework":
                    item["installPath"] = native.TARGETS["NodeMobile"]
                else:
                    item["installPaths"] = ["AI_HLY/RuntimeHostResources.zip"]
                records.append(item)
                archives[name] = path
            catalog = {"state": "published", "releaseTag": "fixture",
                       "artifacts": [records[0], {"target": "Python"}],
                       "supportArtifacts": [records[1], {"target": "HanlinExpoHeaderSupport"}]}
            requested = []
            def get(item, cache):
                requested.append(item["target"])
                return archives[item["target"]]
            # Native slice validation is independently proved against the frozen
            # real NodeMobile artifact. This fixture tests the actual installer IO.
            with patch.object(native, "download", side_effect=get), patch.object(native, "framework_libraries"):
                native.install(catalog, sdk, root / "cache", ["NodeMobile"], True)
            self.assertEqual(requested, ["NodeMobile", "HanlinNodeHostSupport"])
            self.assertTrue((sdk / "AI_HLY/RuntimeHostResources.zip").is_file())
            self.assertFalse((sdk / "Vendor/Python").exists())
            self.assertFalse((sdk / "Packages/HanlinExpoRuntime").exists())

    def test_catalog_rejects_retargeted_url_and_changed_content_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checksum = "a" * 64
            identity = hashlib.sha256(json.dumps({"NodeMobile": checksum}, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            tag = "sdk-native-v1-" + identity
            item = {"target": "NodeMobile", "kind": "xcframework",
                    "installPath": native.TARGETS["NodeMobile"], "root": "NodeMobile.xcframework",
                    "archive": "NodeMobile.xcframework.zip", "checksum": checksum,
                    "url": f"https://github.com/{native.REPOSITORY}/releases/download/{tag}/NodeMobile.xcframework.zip"}
            catalog = {"schemaVersion": 1, "repository": native.REPOSITORY, "releaseTag": tag,
                       "artifacts": [item], "supportArtifacts": []}
            path = root / "catalog.json"
            native.json_write(path, catalog)
            self.assertEqual(native.load_catalog(path)["releaseTag"], tag)
            item["url"] = "https://example.invalid/unpinned.zip"
            native.json_write(path, catalog)
            with self.assertRaisesRegex(ValueError, "URL does not match"):
                native.load_catalog(path)
            item["url"] = f"https://github.com/{native.REPOSITORY}/releases/download/{tag}/NodeMobile.xcframework.zip"
            item["checksum"] = "b" * 64
            native.json_write(path, catalog)
            with self.assertRaisesRegex(ValueError, "content identity mismatch"):
                native.load_catalog(path)


if __name__ == "__main__":
    unittest.main()
