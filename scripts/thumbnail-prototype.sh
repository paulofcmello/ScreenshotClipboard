#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build/thumbnail-prototype
if [[ "${1:-}" == --make-fixture ]]; then
  xcrun swiftc -O -module-cache-path build/ModuleCache \
    Prototypes/Thumbnail/TestSupport.swift -o build/thumbnail-prototype/test-support
  exec build/thumbnail-prototype/test-support "$@"
fi
flags=()
for arg in "$@"; do
  case "$arg" in
    --benchmark|--verify-clipboard|--render-preview) flags=(-D MEASURE) ;;
  esac
done
xcrun swiftc -O -whole-module-optimization -module-cache-path build/ModuleCache "${flags[@]}" \
  Prototypes/Thumbnail/main.swift -o build/thumbnail-prototype/thumbnail
exec build/thumbnail-prototype/thumbnail "$@"
