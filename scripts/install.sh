#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_source="$task_root/dist/CPAMC Menu Bar.app"
task_dest="$HOME/Applications/CPAMC Menu Bar.app"
if [ ! -d "$task_source" ]; then
  bash "$task_root/scripts/build.sh"
fi
if [ -d "$task_dest" ]; then
  task_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_dest/Contents/Info.plist" 2>/dev/null || true)
  if [ "$task_id" != "ai.notis.cpamc-menubar" ]; then
    printf 'Refusing to overwrite an unrelated application: %s\n' "$task_dest" >&2
    exit 1
  fi
  # Quit only this app, never CPAMC, CLIProxyAPI, Quotio or Notis.
  osascript -e 'tell application id "ai.notis.cpamc-menubar" to quit' 2>/dev/null || true
fi
mkdir -p "$HOME/Applications"
ditto "$task_source" "$task_dest"
if [ "${1:-}" = "--login" ]; then
  open "$task_dest" --args --enable-login
else
  open "$task_dest"
fi
printf 'Installed and opened: %s\n' "$task_dest"
