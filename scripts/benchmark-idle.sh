#!/bin/zsh
set -eu
cd "${0:A:h:h}"
output=build/performance
baseline_ref="${1:-HEAD}"
mkdir -p "$output/baseline" "$output/optimized"
for file in Core.swift Management.swift main.swift; do
  git show "$baseline_ref:Sources/$file" > "$output/baseline/$file"
done
xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache \
  "$output/baseline/Core.swift" "$output/baseline/Management.swift" "$output/baseline/main.swift" -o "$output/baseline/daemon"
xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache \
  Sources/Core.swift Sources/Management.swift Sources/main.swift -o "$output/optimized/daemon"
xcrun swiftc -O -module-cache-path build/ModuleCache Benchmarks/Process/main.swift -o "$output/process-resources"
for variant in baseline optimized; do
  "$output/process-resources" "$output/$variant/daemon" > "$output/$variant/daemon-idle.json"
done
