#!/bin/bash
set -euo pipefail
task_app="$HOME/Applications/Juice Bar.app"
task_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$task_app/Contents/Info.plist" 2>/dev/null || true; }
# Recognized by its executable; the bundle ID is read, so earlier builds are removed too.
if [ "$(task_plist CFBundleExecutable)" != "cpamc-menubar" ]; then
  printf 'Juice Bar is not installed at the expected path. No files changed.\n'
  exit 0
fi
task_id="$(task_plist CFBundleIdentifier)"
task_agent="$HOME/Library/LaunchAgents/$task_id.plist"
if [ -n "$(lsappinfo find bundleid="$task_id")" ]; then
  osascript -e 'on run argv' -e 'tell application id (item 1 of argv) to quit' -e 'end run' "$task_id" >/dev/null 2>&1 || true
fi
"$task_app/Contents/MacOS/cpamc-menubar" --disable-login
if [ -f "$task_agent" ]; then
  launchctl bootout "gui/$(id -u)" "$task_agent" 2>/dev/null || true
  rm "$task_agent"
fi
# Move only our own bundle to the Trash. Accounts and proxy files remain untouched.
mkdir -p "$HOME/.Trash"
mv "$task_app" "$HOME/.Trash/Juice Bar-$(date +%Y%m%d-%H%M%S).app"
# The updater's source, build cache and log; settings stay where they are.
rm -rf "$HOME/Library/Application Support/Juice Bar"
printf 'Juice Bar moved to Trash. Your proxy and credentials are unchanged.\n'
