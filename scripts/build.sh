#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache \
  Sources/Core.swift Sources/Management.swift Sources/main.swift \
  -o build/screenshot-clipboard
codesign --force --sign - --identifier local.screenshot-clipboard build/screenshot-clipboard
