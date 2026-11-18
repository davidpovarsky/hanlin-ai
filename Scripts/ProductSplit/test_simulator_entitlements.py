"""Negative-input coverage for the native evidence reader, not product acceptance."""
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from simulator_entitlements import read_simulator_entitlements


def executable(payload=None, sections=1, offset_override=None):
    payload = payload if payload is not None else plistlib.dumps({
        "com.apple.security.application-groups": ["group.com.itorah.chavrusachat"]})
    command_size = 72 + 80 * sections
    offset = 32 + command_size
    header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, command_size, 0, 0)
    segment = struct.pack("<II16sQQQQIIII", 0x19, command_size, b"__TEXT", 0, offset + len(payload),
                          0, offset + len(payload), 7, 5, sections, 0)
    section = struct.pack("<16s16sQQIIIIIIII", b"__entitlements", b"__TEXT", 0, len(payload),
                          offset if offset_override is None else offset_override, 0, 0, 0, 0, 0, 0, 0)
    return header + segment + section * sections + payload


class SimulatorEntitlementsTests(unittest.TestCase):
    def read(self, contents):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "NativeApp"
            path.write_bytes(contents)
            return read_simulator_entitlements(path)

    def test_actual_embedded_plist_is_read_without_signature_entitlements(self):
        proof = self.read(executable())
        self.assertEqual(proof["entitlements"]["com.apple.security.application-groups"],
                         ["group.com.itorah.chavrusachat"])
        self.assertEqual(proof["source"], "__TEXT,__entitlements")
        self.assertEqual(len(proof["executable_sha256"]), 64)

    def test_ambiguous_or_absent_sections_are_rejected(self):
        for count in [0, 2]:
            with self.subTest(count=count), self.assertRaises(ValueError):
                self.read(executable(sections=count))

    def test_truncated_executable_is_rejected(self):
        for payload in [b"", executable()[:31], executable()[:-1]]:
            with self.subTest(length=len(payload)), self.assertRaises(ValueError):
                self.read(payload)

    def test_entitlements_cannot_point_into_commands_or_outside_file(self):
        for offset in [0, 32, 1000000]:
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.read(executable(offset_override=offset))

    def test_unexpected_architecture_or_file_type_is_rejected(self):
        original = executable()
        for offset, value in [(0, 0xCAFEBABE), (4, 0x01000007), (12, 6)]:
            changed = bytearray(original)
            struct.pack_into("<I", changed, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.read(changed)

    def test_invalid_plist_or_non_dictionary_is_rejected(self):
        for payload in [b"not an entitlement plist", plistlib.dumps(["group.com.itorah.chavrusachat"])]:
            with self.subTest(payload=payload[:20]), self.assertRaises(ValueError):
                self.read(executable(payload))


if __name__ == "__main__":
    unittest.main()
