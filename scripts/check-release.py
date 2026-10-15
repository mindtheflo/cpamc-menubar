#!/usr/bin/env python3
"""Check the screenshot freshness and minimal README contracts used by the release skill and CI."""
import json
import re
from pathlib import Path

from release_assets import PAGES, image_record, source_digest

root = Path(__file__).resolve().parent.parent
readme = (root / "README.md").read_text()
words = len(re.sub(r"<[^>]+>", "", readme).split())
if words > 180:
    raise SystemExit(f"README has {words} words; keep marketing and install to at most 180.")
if re.findall(r"^## (.+)$", readme, re.M) != ["Install"]:
    raise SystemExit("README sections must be marketing + Install. Put technical details in docs/development.md.")
links = re.findall(r'(?:src|href)="([^"]+)"', readme) + re.findall(r'\]\(([^)]+)\)', readme)
for link in links:
    if not re.match(r"(?:https?://|#)", link) and not (root / link.split("#")[0]).is_file():
        raise SystemExit(f"README link missing: {link}")
folder = root / "assets/screenshots"
manifest_path = folder / "manifest.json"
if not manifest_path.exists():
    raise SystemExit("Run python3 scripts/capture-screenshots.py to capture release screenshots first.")
manifest = json.loads(manifest_path.read_text())
if manifest.get("schema") != 1 or manifest.get("source_sha256") != source_digest(root):
    raise SystemExit("Screenshots predate the current app or capture workflow. Run python3 scripts/capture-screenshots.py.")
for page in PAGES:
    name = f"{page}.png"
    if manifest["images"].get(name) != image_record(folder / name):
        raise SystemExit(f"Screenshot {name} differs from its capture manifest. Recapture the native app.")
print(f"Release assets checked: README {words}/180 words; three native screenshots match current source.")
