#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache \
  Sources/Core.swift Tests/main.swift -o build/tests
./build/tests
