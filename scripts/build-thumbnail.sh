#!/bin/zsh
set -eu
cd "${0:A:h:h}"
zsh scripts/check-environment.sh
app=build/active-app/ScreenshotClipboard.app
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -O -whole-module-optimization -module-cache-path build/ModuleCache Sources/Hotkeys/main.swift -o "$app/Contents/MacOS/screenshot-clipboard"
xcrun swiftc -O -whole-module-optimization -module-cache-path build/ModuleCache Sources/Capture/main.swift -o "$app/Contents/MacOS/capture"
python3 - <<'PY'
import plistlib
from pathlib import Path
info = {'CFBundleIdentifier':'local.screenshot-clipboard','CFBundleName':'ScreenshotClipboard',
        'CFBundleExecutable':'screenshot-clipboard','CFBundlePackageType':'APPL',
        'CFBundleShortVersionString':'2.0','CFBundleVersion':'2',
        'LSUIElement':True,'NSHighResolutionCapable':True}
Path('build/active-app/ScreenshotClipboard.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$app/Contents/MacOS/capture"
codesign --force --sign - "$app"
settings="build/settings-app/Screenshot Clipboard.app"
mkdir -p "$settings/Contents/MacOS"
xcrun swiftc -O -whole-module-optimization -module-cache-path build/ModuleCache Sources/Settings/main.swift -o "$settings/Contents/MacOS/settings"
python3 - <<'PY'
import plistlib
from pathlib import Path
info = {'CFBundleIdentifier':'local.screenshot-clipboard.settings','CFBundleName':'Screenshot Clipboard',
        'CFBundleExecutable':'settings','CFBundlePackageType':'APPL',
        'CFBundleShortVersionString':'2.0','CFBundleVersion':'2',
        'LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,
        'CFBundleIconFile':'AppIcon'}
Path('build/settings-app/Screenshot Clipboard.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
iconset=build/AppIcon.iconset
mkdir -p "$iconset" "$settings/Contents/Resources"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$settings/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$settings"
