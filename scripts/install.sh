#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_id="io.github.mindtheflo.juice-bar"
task_build="$task_root/.build/app"
task_dest="$HOME/Applications/Juice Bar.app"
task_legacy="$HOME/Applications/CPAMC Menu Bar.app"
task_login="${1:-}"
task_relogin=

task_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }

# Asks a running copy to quit and waits for it, so the new build is the one that opens.
task_quit() {
  [ -n "$(lsappinfo find bundleid="$1")" ] || return 0
  osascript -e 'on run argv' -e 'tell application id (item 1 of argv) to quit' -e 'end run' "$1" >/dev/null 2>&1 || true
  for _ in $(seq 100); do
    [ -n "$(lsappinfo find bundleid="$1")" ] || return 0
    sleep 0.1
  done
  printf 'Juice Bar did not quit. Quit it from its menu, then run this again.\n' >&2
  exit 1
}

# Earlier builds used another bundle ID: copy their preferences once and remove their login item.
task_migrate() {
  local task_old="$1" task_app="$2" task_pid
  local task_agent="$HOME/Library/LaunchAgents/$task_old.plist"
  if defaults read "$task_old" >/dev/null 2>&1 && ! defaults read "$task_id" >/dev/null 2>&1; then
    defaults export "$task_old" - | defaults import "$task_id" -
  fi
  "$task_app/Contents/MacOS/cpamc-menubar" --disable-login >/dev/null 2>&1 &
  task_pid=$!
  for _ in $(seq 100); do
    kill -0 "$task_pid" 2>/dev/null || break
    sleep 0.1
  done
  kill "$task_pid" 2>/dev/null || true
  wait "$task_pid" 2>/dev/null || true
  if [ -f "$task_agent" ] && grep -q cpamc-menubar "$task_agent"; then
    launchctl bootout "gui/$(id -u)" "$task_agent" 2>/dev/null || true
    rm "$task_agent"
  fi
  task_relogin=1
}

# Earlier builds are recognized by their executable; their bundle ID is read, not assumed.
for task_existing in "$task_dest" "$task_legacy"; do
  if [ -e "$task_existing" ] && [ "$(task_plist "$task_existing" CFBundleExecutable)" != "cpamc-menubar" ]; then
    printf 'Refusing to replace an unrelated application: %s\n' "$task_existing" >&2
    exit 1
  fi
done
# Built from source, so the app is never quarantined and needs no notarization to open.
bash "$task_root/scripts/build.sh" "$task_build"
for task_existing in "$task_dest" "$task_legacy"; do
  [ -d "$task_existing" ] || continue
  task_old="$(task_plist "$task_existing" CFBundleIdentifier)"
  [ -n "$task_old" ] || continue
  task_quit "$task_old"
  if [ "$task_old" != "$task_id" ]; then
    task_migrate "$task_old" "$task_existing"
  fi
done
task_quit "$task_id"
# Swap in a complete copy; the configuration file and preferences are left untouched.
mkdir -p "$HOME/Applications"
task_stage="$HOME/Applications/.Juice Bar.installing-$$"
rm -rf "$task_stage" "$task_stage.old"
ditto "$task_build/Juice Bar.app" "$task_stage"
if [ -e "$task_dest" ]; then
  mv "$task_dest" "$task_stage.old"
fi
mv "$task_stage" "$task_dest"
rm -rf "$task_stage.old"
if [ -d "$task_legacy" ]; then
  mkdir -p "$HOME/.Trash"
  mv "$task_legacy" "$HOME/.Trash/CPAMC Menu Bar-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
# Opened in the background: a menu-bar app has no window to bring forward.
if [ "$task_login" = "--login" ]; then
  open -g "$task_dest" --args --enable-login
else
  open -g "$task_dest"
fi
printf 'Installed and opened: %s (%s)\n' "$task_dest" "$(task_plist "$task_dest" CFBundleShortVersionString)"
if [ -n "$task_relogin" ] && [ "$task_login" != "--login" ]; then
  printf 'Launch at login was reset for the new app identity. Turn it on in Settings, or run this with --login.\n'
fi
