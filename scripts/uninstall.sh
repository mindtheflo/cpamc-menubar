#!/bin/bash
set -euo pipefail
task_app="$HOME/Applications/Juice Bar.app"
task_agent="$HOME/Library/LaunchAgents/ai.notis.cpamc-menubar.plist"
task_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_app/Contents/Info.plist" 2>/dev/null || true)
if [ "$task_id" != "ai.notis.cpamc-menubar" ]; then
  printf 'Juice Bar is not installed at the expected path. No files changed.\n'
  exit 0
fi
osascript -e 'tell application id "ai.notis.cpamc-menubar" to quit' 2>/dev/null || true
"$task_app/Contents/MacOS/cpamc-menubar" --disable-login
if [ -f "$task_agent" ]; then
  launchctl bootout "gui/$(id -u)" "$task_agent" 2>/dev/null || true
  rm "$task_agent"
fi
# Move only our own bundle to the Trash. Accounts and proxy files remain untouched.
mkdir -p "$HOME/.Trash"
mv "$task_app" "$HOME/.Trash/Juice Bar-$(date +%Y%m%d-%H%M%S).app"
printf 'Juice Bar moved to Trash. Your proxy and credentials are unchanged.\n'
