"""Focused exporter integrity tests; fixture bytes are never native acceptance evidence."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "native_artifacts.py"
spec = importlib.util.spec_from_file_location("native_artifacts", SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def versioned_fixture(root):
    # This small fixture checks packaging behavior only. The source-bound
    # acceptance also exports both genuine, locked NativeScript frameworks.
    source = root / "Versioned.xcframework"
    source.mkdir()
    libraries = []
    for variant in ("device", "simulator", "maccatalyst"):
        identifier = "ios-arm64" + ("-" + variant if variant != "device" else "")
        framework = source / identifier / "Versioned.framework"
        version = framework / "Versions/A" if variant == "maccatalyst" else framework
        metadata = version / "Resources/Info.plist" if variant == "maccatalyst" else version / "Info.plist"
        metadata.parent.mkdir(parents=True)
        metadata.write_bytes(plistlib.dumps({"CFBundleExecutable": "Versioned"}))
        (version / "Versioned").write_bytes(b"!<arch>\npackaging-only-test-fixture")
        (version / "Versioned").chmod(0o755)
        if variant == "maccatalyst":
            (framework / "Versions/Current").symlink_to("A")
            (framework / "Resources").symlink_to("Versions/Current/Resources")
        binary = "Versioned.framework/" + ("Versions/Current/" if variant == "maccatalyst" else "") + "Versioned"
        libraries.append({"LibraryIdentifier": identifier, "LibraryPath": "Versioned.framework",
                          "BinaryPath": binary, "SupportedPlatform": "ios", "SupportedArchitectures": ["arm64"],
                          **({"SupportedPlatformVariant": variant} if variant != "device" else {})})
    (source / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))
    return source, libraries


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

    def test_versioned_framework_metadata_binary_paths_and_link_chain_roundtrip(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, _ = versioned_fixture(root)
            libraries = native.framework_libraries(source, "Versioned")
            self.assertEqual(len(libraries), 3)
            catalyst = next(item for item in libraries if item["variant"] == "maccatalyst")
            self.assertEqual(catalyst["binary"], "ios-arm64-maccatalyst/Versioned.framework/Versions/A/Versioned")
            archive = root / "Versioned.xcframework.zip"
            native.archive_paths(archive, [(source, native.PurePosixPath(source.name))])
            catalog = {"artifacts": [{"archive": archive.name, "checksum": native.digest(archive),
                "bytes": archive.stat().st_size, "kind": "xcframework", "root": source.name,
                "target": "Versioned", "libraries": libraries}], "supportArtifacts": []}
            native.verify(catalog, root)
            output = root / "installed"
            output.mkdir()
            native.extract_verified(archive, native.digest(archive), output, source.name)
            self.assertEqual(native.framework_libraries(output / source.name, "Versioned"), libraries)
            framework = output / source.name / "ios-arm64-maccatalyst/Versioned.framework"
            self.assertTrue((framework / "Resources").is_symlink())
            self.assertTrue((framework / "Versions/Current").is_symlink())
            self.assertEqual((framework / "Resources/Info.plist").read_bytes(),
                             (framework / "Versions/A/Resources/Info.plist").read_bytes())
            self.assertTrue((framework / "Versions/A/Versioned").stat().st_mode & stat.S_IXUSR)

    def test_versioned_framework_rejects_foreign_binary_metadata_and_missing_platform(self):
        for mutation in ("foreign_binary", "executable_mismatch", "foreign_metadata", "missing_simulator"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source, libraries = versioned_fixture(root)
                item = libraries[-1]
                framework = source / item["LibraryIdentifier"] / item["LibraryPath"]
                if mutation == "foreign_binary":
                    item["BinaryPath"] = "Other.framework/Versioned"
                elif mutation == "executable_mismatch":
                    item["BinaryPath"] = "Versioned.framework/Versions/A/AnotherName"
                elif mutation == "foreign_metadata":
                    (framework / "Resources").unlink()
                    (framework / "Resources").symlink_to(root)
                    (root / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Versioned"}))
                else:
                    libraries[:] = [value for value in libraries if value.get("SupportedPlatformVariant") != "simulator"]
                (source / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))
                with self.assertRaises(ValueError):
                    native.framework_libraries(source, "Versioned")

    def test_deferred_internal_links_still_reject_a_resolved_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "chain.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("Native.xcframework/deep/keep", b"fixture")
                for name, target in (("alias", ".."), ("escape", "alias/../../outside")):
                    info = zipfile.ZipInfo("Native.xcframework/deep/" + name)
                    info.create_system = 3
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    stream.writestr(info, target)
            output = root / "installed"
            output.mkdir()
            with self.assertRaisesRegex(ValueError, "escapes its root"):
                native.extract_verified(archive, native.digest(archive), output, "Native.xcframework")

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
            spec = importlib.util.spec_from_file_location("native_selection_fixture",
                Path(__file__).with_name("test_native_provenance.py"))
            fixture_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(fixture_module)
            fixture = fixture_module.NativeSourceFixture(root)
            sdk = fixture.sdk
            fixture.catalog["artifacts"].append({"target": "Python"})
            fixture.catalog["supportArtifacts"].append({"target": "HanlinExpoHeaderSupport"})
            shutil.rmtree(sdk / "Vendor")
            fixture.host_archive.unlink()
            fixture.native_receipt.unlink()
            requested = []
            def get(item, cache):
                requested.append(item["target"])
                return fixture.archives[item["target"]]
            # Slice acceptance remains bound to the genuine frozen Node artifact.
            # The fixture now also carries pinned sources and a valid Host ZIP.
            with patch.object(native, "download", side_effect=get), patch.object(native, "framework_libraries"):
                native.install(fixture.catalog, sdk, root / "cache", ["NodeMobile"], True)
            self.assertEqual(requested, ["NodeMobile", "HanlinExpoWidgetRuntimeSupport", "HanlinNodeHostSupport"])
            self.assertTrue((sdk / "AI_HLY/RuntimeHostResources.zip").is_file())
            self.assertFalse((sdk / "Vendor/Python").exists())
            # Node's canonical SDK fingerprint needs this small resource
            # carrier, but no Expo framework, headers or other source payload.
            expo_root = sdk / "Packages/HanlinExpoRuntime"
            self.assertEqual({str(path.relative_to(sdk)) for path in expo_root.rglob("*") if path.is_file()},
                             native.PREPARED_WIDGET_FILES)
            self.assertFalse((expo_root / "Artifacts").exists())

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
