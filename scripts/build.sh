#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_sign_identity="${CODESIGN_IDENTITY:--}"
swift build -c release
task_bin="$(swift build -c release --show-bin-path)"
task_app="$task_root/dist/Juice Bar.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin/cpamc-menubar" "$task_app/Contents/MacOS/cpamc-menubar"
cp "$task_bin/cpamc-quota-check" "$task_app/Contents/MacOS/cpamc-quota-check"
cp "$task_root/assets/AppIcon.icns" "$task_app/Contents/Resources/AppIcon.icns"
cp "$task_root/LICENSE" "$task_app/Contents/Resources/LICENSE"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>cpamc-menubar</string>
  <key>CFBundleIdentifier</key><string>ai.notis.cpamc-menubar</string>
  <key>CFBundleName</key><string>Juice Bar</string>
  <key>CFBundleDisplayName</key><string>Juice Bar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIconFiles</key><array><string>AppIcon.icns</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>ai.notis.cpamc-menubar</string>
    <key>CFBundleURLSchemes</key><array><string>cpamc-menubar</string></array>
  </dict></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSHumanReadableCopyright</key><string>2026 Florian Pariset · MIT License</string>
</dict></plist>
PLIST
codesign --force --deep --options runtime --timestamp --sign "$task_sign_identity" "$task_app"
task_zip="$task_root/dist/Juice Bar.app.zip"
rm -f "$task_zip"
ditto -c -k --norsrc --keepParent "$task_app" "$task_zip"
bash "$task_root/scripts/build-plugin.sh"
printf 'Built: %s\nArchive: %s\n' "$task_app" "$task_zip"
