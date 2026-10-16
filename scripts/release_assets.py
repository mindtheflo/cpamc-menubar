"""Shared release-asset metadata; standard library only."""
import hashlib
import struct
from pathlib import Path

PAGES = ("overview", "account", "settings")


def source_digest(root: Path) -> str:
    paths = sorted((root / "Sources").rglob("*.swift")) + [
        root / "Package.swift", root / "scripts/capture-screenshots.py",
        root / "scripts/screenshot-window.swift", root / "scripts/release_assets.py",
    ]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def image_record(path: Path) -> dict:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    width, height = struct.unpack(">II", data[16:24])
    return {"sha256": hashlib.sha256(data).hexdigest(), "width": width, "height": height}
