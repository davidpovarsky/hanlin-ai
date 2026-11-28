"""Read Xcode's actual simulator entitlements from a thin arm64 executable.

Layout: apple-oss-distributions/cctools, include/mach-o/loader.h.
Xcode 27 embeds the simulator plist in __TEXT,__entitlements; an ad-hoc
codesign signature can legitimately contain an empty entitlement dictionary.
This reader does not replace signature verification or OS container checks.
"""
from pathlib import Path
import hashlib
import plistlib
import struct


def read_simulator_entitlements(executable: Path):
    with executable.open("rb") as stream:
        file_size = executable.stat().st_size
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError("Truncated Mach-O header")
        magic, cpu, _, kind, count, size, _, _ = struct.unpack("<8I", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2:
            raise ValueError("Expected the actual thin arm64 simulator executable")
        if not 0 < count <= size // 8 or size > 4 * 1024 * 1024 or 32 + size > file_size:
            raise ValueError("Invalid Mach-O load command bounds")
        commands = stream.read(size)
        position, found = 0, []
        for _ in range(count):
            if position + 8 > size:
                raise ValueError("Truncated Mach-O load command")
            cmd, length = struct.unpack_from("<II", commands, position)
            if length < 8 or length % 8 or position + length > size:
                raise ValueError("Invalid Mach-O load command size")
            if cmd == 0x19:  # LC_SEGMENT_64
                if length < 72:
                    raise ValueError("Truncated Mach-O segment")
                segment = struct.unpack_from("<II16sQQQQIIII", commands, position)
                name, file_offset, file_bytes, sections = segment[2], segment[5], segment[6], segment[9]
                if 72 + sections * 80 != length:
                    raise ValueError("Invalid Mach-O section table")
                for index in range(sections):
                    section = struct.unpack_from("<16s16sQQI", commands, position + 72 + index * 80)
                    section_name, segment_name, _, section_size, offset = section
                    if name.rstrip(b"\0") == b"__TEXT" and segment_name.rstrip(b"\0") == b"__TEXT" \
                            and section_name.rstrip(b"\0") == b"__entitlements":
                        if not 0 < section_size <= 1024 * 1024 or offset < 32 + size \
                                or offset < file_offset or offset + section_size > file_offset + file_bytes \
                                or offset + section_size > file_size:
                            raise ValueError("Invalid embedded entitlement bounds")
                        found.append((offset, section_size))
            position += length
        if position != size or len(found) != 1:
            raise ValueError("Expected exactly one simulator entitlement section")
        offset, section_size = found[0]
        stream.seek(offset)
        payload = stream.read(section_size)
        entitlements = plistlib.loads(payload.rstrip(b"\0"))
        if not isinstance(entitlements, dict):
            raise ValueError("Embedded entitlements must be a plist dictionary")
        stream.seek(0)
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return {"source": "__TEXT,__entitlements", "executable": executable.name,
            "executable_sha256": digest.hexdigest(), "offset": offset, "bytes": section_size,
            "section_sha256": hashlib.sha256(payload).hexdigest(), "entitlements": entitlements}
