from __future__ import annotations

import importlib.util
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "validate-app-dyld-closure.py"
SPEC = importlib.util.spec_from_file_location("validate_app_dyld_closure", SCRIPT_PATH)
assert SPEC and SPEC.loader
SCANNER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SCANNER
SPEC.loader.exec_module(SCANNER)
MACHO_BYTES = b"\xcf\xfa\xed\xfe" + (b"\x00" * 28)


def inspection(
    *,
    install_id: str | None = None,
    dependencies: tuple[str, ...] = ("/usr/lib/libSystem.B.dylib",),
    rpaths: tuple[str, ...] = ("@executable_path/Frameworks",),
    architectures: tuple[str, ...] = ("arm64",),
    platforms: tuple[str, ...] = ("IOS",),
) -> object:
    return SCANNER.MachOInspection(
        file_description="Mach-O 64-bit dynamically linked",
        install_ids=(install_id,) if install_id else (),
        dependencies=dependencies,
        rpaths=rpaths,
        architectures=architectures,
        apple_platforms=platforms,
        minimum_os_versions=("14.0",),
    )


class FakeToolchain:
    def __init__(self, app: Path, inspections: dict[str, object]) -> None:
        self.app = app
        self.inspections = inspections

    def inspect(self, binary: Path) -> object:
        return self.inspections[binary.relative_to(self.app).as_posix()]


class AppleToolParsingTests(unittest.TestCase):
    def test_parses_plain_lipo_arch_list(self) -> None:
        self.assertEqual(SCANNER.AppleToolchain._parse_architectures("arm64 arm64e\n"), ["arm64", "arm64e"])

    def test_parses_install_id_and_dependencies_separately(self) -> None:
        binary = Path("/tmp/PythonSSL")
        install_id = "Modules/_ssl.cpython-314-iphoneos.so"
        self.assertEqual(
            SCANNER.AppleToolchain._parse_otool_ids(f"{binary}:\n{install_id}\n", binary),
            [install_id],
        )
        self.assertEqual(
            SCANNER.AppleToolchain._parse_otool_dependencies(
                f"{binary}:\n\t{install_id} (compatibility version 0.0.0, current version 0.0.0)\n",
                binary,
            ),
            [install_id],
        )

    def test_parses_vtool_device_build_version(self) -> None:
        platforms, minimum_versions = SCANNER.AppleToolchain._parse_build_versions(
            "Load command 10\n      cmd LC_BUILD_VERSION\n platform IOS\n    minos 14.0\n",
            "",
        )
        self.assertEqual(platforms, ["IOS"])
        self.assertEqual(minimum_versions, ["14.0"])


class DyldClosureScannerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.app = Path(self.temporary.name) / "Fixture.app"
        self.app.mkdir()
        self.inspections: dict[str, object] = {}
        self.add_binary("Fixture", inspection())

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def add_binary(self, relative: str, metadata: object) -> Path:
        path = self.app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(MACHO_BYTES)
        self.inspections[relative] = metadata
        return path

    def add_framework(
        self,
        name: str,
        metadata: object,
        *,
        executable: str | None = None,
        identifier: str | None = None,
    ) -> Path:
        executable = executable or name
        framework = self.app / "Frameworks" / f"{name}.framework"
        framework.mkdir(parents=True, exist_ok=True)
        with (framework / "Info.plist").open("wb") as stream:
            plistlib.dump(
                {
                    "CFBundleExecutable": executable,
                    "CFBundleIdentifier": identifier or f"test.{name}",
                },
                stream,
            )
        return self.add_binary(f"Frameworks/{name}.framework/{executable}", metadata)

    def scan(self, platform: str = "iphoneos") -> dict[str, object]:
        return SCANNER.scan_app(self.app, platform, FakeToolchain(self.app, self.inspections))

    def test_catches_missing_libssh2(self) -> None:
        self.add_framework(
            "curl_ios",
            inspection(
                install_id="@rpath/curl_ios.framework/curl_ios",
                dependencies=("@rpath/libssh2.framework/libssh2",),
            ),
        )
        report = self.scan()
        self.assertEqual(report["result"], "fail")
        self.assertEqual(report["unresolvedDependencies"][0]["dependency"], "@rpath/libssh2.framework/libssh2")

    def test_catches_missing_openssl(self) -> None:
        self.add_framework(
            "curl_ios",
            inspection(
                install_id="@rpath/curl_ios.framework/curl_ios",
                dependencies=("@rpath/openssl.framework/openssl",),
            ),
        )
        report = self.scan()
        self.assertEqual(report["result"], "fail")
        self.assertEqual(report["unresolvedDependencies"][0]["dependency"], "@rpath/openssl.framework/openssl")

    def test_catches_unexpected_users_path(self) -> None:
        self.inspections["Fixture"] = inspection(dependencies=("/Users/developer/build/libbad.dylib",))
        report = self.scan()
        self.assertEqual(report["result"], "fail")
        self.assertIn("forbidden developer-machine path", report["unresolvedDependencies"][0]["message"])

    def test_catches_simulator_framework_in_device_app(self) -> None:
        self.add_framework(
            "SimulatorOnly",
            inspection(
                install_id="@rpath/SimulatorOnly.framework/SimulatorOnly",
                platforms=("IOS_SIMULATOR",),
            ),
        )
        report = self.scan()
        self.assertEqual(report["result"], "fail")
        simulator = next(binary for binary in report["binaries"] if "SimulatorOnly.framework" in binary["path"])
        self.assertTrue(any("platform mismatch" in error for error in simulator["errors"]))

    def test_allows_recognized_apple_system_libraries(self) -> None:
        self.inspections["Fixture"] = inspection(
            dependencies=(
                "/System/Library/Frameworks/Foundation.framework/Foundation",
                "/usr/lib/libSystem.B.dylib",
            )
        )
        self.assertEqual(self.scan()["result"], "pass")

    def test_ignores_python_extension_own_relative_install_id(self) -> None:
        install_id = "Modules/_ssl.cpython-314-iphoneos.so"
        self.add_framework(
            "PythonSSL",
            inspection(install_id=install_id, dependencies=(install_id, "/usr/lib/libSystem.B.dylib")),
            executable="_ssl.cpython-314-iphoneos.so",
        )
        report = self.scan()
        self.assertEqual(report["result"], "pass")
        extension = next(binary for binary in report["binaries"] if "PythonSSL.framework" in binary["path"])
        self.assertEqual(extension["directDependencies"][0]["status"], "self")

    def test_rejects_other_relative_dependency_beside_own_install_id(self) -> None:
        install_id = "Modules/_ssl.cpython-314-iphoneos.so"
        self.add_framework(
            "PythonSSL",
            inspection(install_id=install_id, dependencies=(install_id, "Modules/not-self.so")),
            executable="_ssl.cpython-314-iphoneos.so",
        )
        report = self.scan()
        self.assertEqual(report["result"], "fail")
        self.assertIn("unsupported relative dependency", report["unresolvedDependencies"][0]["message"])

    def test_passes_complete_minimal_app_closure(self) -> None:
        self.inspections["Fixture"] = inspection(dependencies=("@rpath/curl_ios.framework/curl_ios",))
        self.add_framework(
            "curl_ios",
            inspection(
                install_id="@rpath/curl_ios.framework/curl_ios",
                dependencies=(
                    "@rpath/libssh2.framework/libssh2",
                    "@rpath/openssl.framework/openssl",
                    "/System/Library/Frameworks/Foundation.framework/Foundation",
                ),
            ),
        )
        self.add_framework(
            "libssh2",
            inspection(
                install_id="@rpath/libssh2.framework/libssh2",
                dependencies=("@rpath/openssl.framework/openssl", "/usr/lib/libz.1.dylib"),
            ),
        )
        self.add_framework(
            "openssl",
            inspection(install_id="@rpath/openssl.framework/openssl"),
        )
        report = self.scan()
        self.assertEqual(report["result"], "pass")
        self.assertEqual(report["unresolvedDependencyCount"], 0)
        self.assertEqual(report["machOCount"], 4)
        self.assertEqual(report["frameworkCount"], 3)


if __name__ == "__main__":
    unittest.main()
