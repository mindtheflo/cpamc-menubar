#!/usr/bin/env python3
"""Capture real native demo panels without touching the installed app or its preferences."""
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from release_assets import PAGES, image_record, source_digest

ROOT = Path(__file__).resolve().parent.parent


def run(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def wait_for_panel(helper: Path, pid: int) -> dict:
    deadline = time.monotonic() + 15
    previous = None
    stable = 0
    while time.monotonic() < deadline:
        windows = json.loads(run(str(helper), str(pid)))
        if windows:
            window = windows[0]
            bounds = window["kCGWindowBounds"]
            stable = stable + 1 if bounds == previous else 0
            previous = bounds
            if stable >= 4 and bounds["Width"] >= 350:
                return window
        time.sleep(0.25)
    raise RuntimeError("No stable demo panel. Run on a logged-in Mac with screen capture allowed.")


def main() -> None:
    subprocess.run(["swift", "build"], cwd=ROOT, check=True)
    binary = Path(run("swift", "build", "--show-bin-path")) / "cpamc-menubar"
    output = ROOT / "assets/screenshots"
    evidence = ROOT / ".context/release-screenshots"
    output.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    helper = evidence / "window-info"
    subprocess.run(["xcrun", "swiftc", "scripts/screenshot-window.swift", "-o", str(helper)], cwd=ROOT, check=True)
    builder = (ROOT / "scripts/build.sh").read_text()
    plist_source = re.search(r"<<'PLIST'\n(.*?)\nPLIST", builder, re.S)
    if not plist_source:
        raise RuntimeError("Cannot find the app's build metadata in scripts/build.sh")
    metadata = plistlib.loads(plist_source.group(1).encode())
    metadata.update(CFBundleIdentifier=f"io.github.mindtheflo.juice-bar.screenshots.{os.getpid()}",
                    CFBundleName="Juice Bar Demo", CFBundleDisplayName="Juice Bar Demo")
    metadata.pop("CFBundleURLTypes", None)  # The demo never registers the installed app's URL scheme.
    with tempfile.TemporaryDirectory(prefix="demo-", dir=evidence) as temporary:
        app = Path(temporary) / "Juice Bar Demo.app/Contents"
        (app / "MacOS").mkdir(parents=True)
        executable = app / "MacOS/cpamc-menubar"
        shutil.copy2(binary, executable)
        (app / "Info.plist").write_bytes(plistlib.dumps(metadata))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
        for page in PAGES:
            with (evidence / f"{page}.log").open("w") as log:
                process = subprocess.Popen([str(executable), "--demo", "--show-menu", "--demo-page", page,
                                            "-language", "en", "-hideAccountNames", "NO"], stdout=log, stderr=log)
                try:
                    panel = wait_for_panel(helper, process.pid)
                    destination = Path(temporary) / f"{page}.png"
                    subprocess.run(["screencapture", "-x", "-o", "-l", str(panel["kCGWindowNumber"]), str(destination)], check=True)
                    record = image_record(destination)
                    if record["width"] < 350 or record["height"] < 100:
                        raise RuntimeError(f"Invalid capture for {page}")
                    shutil.copy2(destination, output / destination.name)
                    print(f"Captured {page}: {record['width']} × {record['height']}", flush=True)
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    manifest = {"schema": 1, "source_sha256": source_digest(ROOT),
                "images": {f"{page}.png": image_record(output / f"{page}.png") for page in PAGES}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Review all three images before committing. Evidence: .context/release-screenshots/")


if __name__ == "__main__":
    main()
