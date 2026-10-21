#!/bin/zsh
# Builds "Screenshot Clipboard.app" (settings app with the background app inside)
# as a universal binary; with DMG=1 also dist/ScreenshotClipboard.dmg for downloads.
set -eu
cd "${0:A:h:h}"
zsh scripts/check-environment.sh

app="build/Screenshot Clipboard.app"
helper="$app/Contents/Helpers/ScreenshotClipboard.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$helper/Contents/MacOS"

# Compile once per architecture and merge, so it runs on Apple Silicon and Intel.
compile() {
  local source=$1 output=$2
  for arch in arm64 x86_64; do
    xcrun swiftc -O -whole-module-optimization -target $arch-apple-macos13.0 \
      -module-cache-path build/ModuleCache "$source" -o "build/$arch-${output:t}"
  done
  lipo -create "build/arm64-${output:t}" "build/x86_64-${output:t}" -output "$output"
}
compile Sources/Settings/main.swift "$app/Contents/MacOS/settings"
compile Sources/Hotkeys/main.swift "$helper/Contents/MacOS/screenshot-clipboard"
compile Sources/Capture/main.swift "$helper/Contents/MacOS/capture"

version=${VERSION:-2.0}
info() {
  cat > "$1/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleName</key><string>$3</string>
  <key>CFBundleExecutable</key><string>$4</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  $5
</dict></plist>
EOF
}
info "$helper" local.screenshot-clipboard ScreenshotClipboard screenshot-clipboard '<key>LSUIElement</key><true/>'
info "$app" local.screenshot-clipboard.settings "Screenshot Clipboard" settings '<key>CFBundleIconFile</key><string>AppIcon</string>'

iconset=build/AppIcon.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

# Free ad-hoc signatures, inside out. A paid Developer ID would remove the
# "unverified developer" step on first open.
codesign --force --sign - "$helper/Contents/MacOS/capture"
codesign --force --sign - "$helper"
codesign --force --sign - "$app"

# The DMG is only for releases (DMG=1); installing from source doesn't need it.
[[ ${DMG:-0} == 1 ]] || { print "Built $app"; exit 0; }
python3 -m venv build/venv
build/venv/bin/pip install --quiet dmgbuild==1.6.7
tiffutil -cathidpicheck Resources/dmg-background.png Resources/dmg-background@2x.png -out build/dmg-background.tiff
mkdir -p dist
rm -f dist/ScreenshotClipboard.dmg
build/venv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$app" -D background=build/dmg-background.tiff \
  "Screenshot Clipboard" dist/ScreenshotClipboard.dmg
print "Built $app and dist/ScreenshotClipboard.dmg"
