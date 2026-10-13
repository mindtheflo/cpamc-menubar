#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_source="$task_root/dist/Juice Bar.app"
task_dest="$HOME/Applications/Juice Bar.app"
task_legacy="$HOME/Applications/CPAMC Menu Bar.app"
if [ ! -d "$task_source" ]; then
  bash "$task_root/scripts/build.sh"
fi
for task_existing in "$task_dest" "$task_legacy"; do
  if [ -d "$task_existing" ]; then
    task_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_existing/Contents/Info.plist" 2>/dev/null || true)
    if [ "$task_id" != "ai.notis.cpamc-menubar" ]; then
      printf 'Refusing to overwrite an unrelated application: %s\n' "$task_existing" >&2
      exit 1
    fi
  fi
done
# Preserve the bundle ID, preference domain, configuration path and plugin scheme.
osascript -e 'tell application id "ai.notis.cpamc-menubar" to quit' 2>/dev/null || true
mkdir -p "$HOME/Applications"
ditto "$task_source" "$task_dest"
# GitHub's content API may normalize executable bits in tracked binary paths.
# Restore the two executable entry points before launching the signed bundle.
chmod 755 "$task_dest/Contents/MacOS/cpamc-menubar" "$task_dest/Contents/MacOS/cpamc-quota-check"
if [ -d "$task_legacy" ]; then
  mkdir -p "$HOME/.Trash"
  mv "$task_legacy" "$HOME/.Trash/CPAMC Menu Bar-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
if [ "${1:-}" = "--login" ]; then
  open "$task_dest" --args --enable-login
else
  open "$task_dest"
fi
printf 'Installed and opened: %s\n' "$task_dest"
