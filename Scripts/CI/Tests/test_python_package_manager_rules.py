from __future__ import annotations

import hashlib
import unittest

MAXIMUM_WHEEL_SIZE_BYTES = 100 * 1024 * 1024


def is_universal_wheel(filename: str, packagetype: str | None = "bdist_wheel") -> bool:
    if packagetype != "bdist_wheel":
        return False
    stem = filename.lower()
    if stem.endswith(".whl"):
        stem = stem[:-4]
    parts = stem.split("-")
    if len(parts) < 3:
        return False
    tags = parts[-3:]
    python_tags = tags[0].split(".")
    is_python3_compatible = any(t == "py3" or t.startswith("py3") for t in python_tags)
    abi_tag = tags[1]
    platform_tag = tags[2]
    return is_python3_compatible and abi_tag == "none" and platform_tag == "any"


def validate_integrity_metadata(sha256: str | None) -> str:
    if sha256 is None:
        raise ValueError("The PyPI distribution is missing required SHA-256 integrity metadata.")
    cleaned = sha256.strip().lower()
    if not cleaned:
        raise ValueError("The PyPI distribution is missing required SHA-256 integrity metadata.")
    if len(cleaned) != 64 or not all(c in "0123456789abcdef" for c in cleaned):
        raise ValueError(f"The PyPI distribution has an invalid SHA-256 digest format: '{cleaned}'.")
    return cleaned


def validate_wheel_size(metadata_size: int | None, actual_size: int | None = None) -> None:
    if metadata_size is not None:
        if metadata_size < 0:
            raise ValueError("PyPI distribution has invalid negative size metadata.")
        if metadata_size > MAXIMUM_WHEEL_SIZE_BYTES:
            raise ValueError("The wheel exceeds the 100 MB package limit.")
    if actual_size is not None:
        if actual_size > MAXIMUM_WHEEL_SIZE_BYTES:
            raise ValueError(f"The downloaded wheel exceeds the 100 MB package limit ({actual_size} bytes).")
        if metadata_size is not None and actual_size != metadata_size:
            raise ValueError(
                f"The downloaded wheel size ({actual_size} bytes) does not match PyPI metadata size ({metadata_size} bytes)."
            )


def verify_wheel_download(data: bytes, expected_sha256: str | None, metadata_size: int | None = None) -> str:
    validate_wheel_size(metadata_size=metadata_size, actual_size=len(data))
    required_hash = validate_integrity_metadata(expected_sha256)
    computed_hash = hashlib.sha256(data).hexdigest().lower()
    if computed_hash != required_hash:
        raise ValueError(
            f"The downloaded wheel failed SHA-256 verification. Expected: {required_hash}, got: {computed_hash}."
        )
    return computed_hash


class PythonPackageManagerRulesTests(unittest.TestCase):
    def test_universal_wheel_accepts_py2_py3_none_any(self) -> None:
        self.assertTrue(is_universal_wheel("six-1.17.0-py2.py3-none-any.whl", "bdist_wheel"))
        self.assertTrue(is_universal_wheel("urllib3-2.2.1-py3-none-any.whl", "bdist_wheel"))
        self.assertTrue(is_universal_wheel("packaging-24.0-py3-none-any.whl", "bdist_wheel"))
        self.assertTrue(is_universal_wheel("custom-1.0-py38.py39.py310-none-any.whl", "bdist_wheel"))

    def test_universal_wheel_rejects_non_universal(self) -> None:
        # Legacy Python 2 only
        self.assertFalse(is_universal_wheel("legacy-1.0-py2-none-any.whl", "bdist_wheel"))
        # Native binary wheels
        self.assertFalse(is_universal_wheel("numpy-1.26.4-cp312-cp312-macosx_11_0_arm64.whl", "bdist_wheel"))
        self.assertFalse(is_universal_wheel("cryptography-42.0.5-cp37-abi3-manylinux_2_28_x86_64.whl", "bdist_wheel"))
        # Source distributions (sdist)
        self.assertFalse(is_universal_wheel("six-1.17.0.tar.gz", "sdist"))
        # Missing packagetype or malformed wheel name
        self.assertFalse(is_universal_wheel("six-1.17.0-py2.py3-none-any.whl", None))
        self.assertFalse(is_universal_wheel("malformed-name.whl", "bdist_wheel"))

    def test_missing_hash_fails_closed(self) -> None:
        payload = b"fake-wheel-content"
        with self.assertRaisesRegex(ValueError, "missing required SHA-256 integrity metadata"):
            verify_wheel_download(payload, None)

        with self.assertRaisesRegex(ValueError, "missing required SHA-256 integrity metadata"):
            verify_wheel_download(payload, "")

        with self.assertRaisesRegex(ValueError, "missing required SHA-256 integrity metadata"):
            verify_wheel_download(payload, "   \n  ")

    def test_hash_mismatch_fails_closed(self) -> None:
        payload = b"legitimate-wheel-bytes"
        tampered_hash = "a" * 64
        with self.assertRaisesRegex(ValueError, "failed SHA-256 verification"):
            verify_wheel_download(payload, tampered_hash)

    def test_malformed_hash_format_fails_closed(self) -> None:
        payload = b"some-bytes"
        with self.assertRaisesRegex(ValueError, "invalid SHA-256 digest format"):
            verify_wheel_download(payload, "not-a-valid-hex-digest")

        with self.assertRaisesRegex(ValueError, "invalid SHA-256 digest format"):
            verify_wheel_download(payload, "abc123")  # too short

    def test_size_exceeding_limit_fails_closed_pre_download(self) -> None:
        oversized = MAXIMUM_WHEEL_SIZE_BYTES + 1
        with self.assertRaisesRegex(ValueError, "exceeds the 100 MB package limit"):
            validate_wheel_size(metadata_size=oversized)

    def test_size_exceeding_limit_fails_closed_post_download(self) -> None:
        # If metadata size was omitted or wrong, actual size still triggers failure
        oversized_actual = MAXIMUM_WHEEL_SIZE_BYTES + 1024
        with self.assertRaisesRegex(ValueError, "exceeds the 100 MB package limit"):
            validate_wheel_size(metadata_size=None, actual_size=oversized_actual)

    def test_size_mismatch_fails_closed(self) -> None:
        actual_data = b"short-data"
        expected_meta_size = 99999
        with self.assertRaisesRegex(ValueError, "does not match PyPI metadata size"):
            validate_wheel_size(metadata_size=expected_meta_size, actual_size=len(actual_data))

    def test_negative_metadata_size_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "invalid negative size"):
            validate_wheel_size(metadata_size=-1)

    def test_valid_wheel_verification_succeeds_and_returns_digest(self) -> None:
        payload = b"universal-wheel-archive-content"
        expected_hash = hashlib.sha256(payload).hexdigest()
        digest = verify_wheel_download(payload, expected_hash, metadata_size=len(payload))
        self.assertEqual(digest, expected_hash)


if __name__ == "__main__":
    unittest.main()
