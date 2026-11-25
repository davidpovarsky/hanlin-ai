"""Read the current app-owned SDK pin without resolving or building Swift packages."""
from pathlib import Path
import argparse
import re

SDK_URL = "https://github.com/davidpovarsky/swift-ai-sdk.git"
CANONICAL_MANIFEST = Path("Packages/HanlinPlatform/Package.swift")
_REVISION_DEPENDENCY = re.compile(
    r'\.package\s*\(\s*url\s*:\s*"([^"]+)"\s*,\s*'
    r'revision\s*:\s*"([^"]+)"\s*,?\s*\)',
    re.DOTALL,
)


def canonical_revision(repository: Path) -> str:
    """Require one exact original-fork revision in the canonical production manifest."""
    source = (repository / CANONICAL_MANIFEST).read_text()
    candidates = [
        (url, revision)
        for url, revision in _REVISION_DEPENDENCY.findall(source)
        if url.rstrip("/").rsplit("/", 1)[-1] in {"swift-ai-sdk", "swift-ai-sdk.git"}
    ]
    if len(candidates) != 1:
        raise ValueError("The canonical manifest must contain one revision-pinned Swift AI SDK dependency.")
    url, revision = candidates[0]
    if url != SDK_URL:
        raise ValueError("The canonical Swift AI SDK dependency must use the original Hanlin fork URL.")
    if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("The canonical Swift AI SDK revision must be a full lowercase 40-character Git SHA.")
    return revision


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", nargs="?", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    try:
        print(canonical_revision(args.repository))
    except (OSError, ValueError) as error:
        parser.error(str(error))
