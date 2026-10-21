#!/bin/zsh
# Builds "Screenshot Clipboard.app" (settings app with the background app inside)
# as a universal binary, plus dist/ScreenshotClipboard.dmg for downloads.
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

mkdir -p dist
rm -rf build/dmg dist/ScreenshotClipboard.dmg
mkdir -p build/dmg
cp -R "$app" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Screenshot Clipboard" -srcfolder build/dmg -format UDZO -quiet dist/ScreenshotClipboard.dmg
print "Built $app and dist/ScreenshotClipboard.dmg"
