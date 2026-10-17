#!/bin/zsh
# Compare a committed baseline with the working tree, sequentially and using
# identical test code / deterministic PNG fixtures. Never install the service.
set -eu
cd "${0:A:h:h}"
zsh scripts/check-environment.sh
baseline_ref="${1:-HEAD}"
output="build/performance"
mkdir -p "$output/baseline" "$output/optimized" build/ModuleCache
baseline_commit=$(git rev-parse "$baseline_ref")
print -r -- "$baseline_commit" > "$output/baseline-commit.txt"
sw_vers > "$output/environment.txt"
xcrun swiftc --version >> "$output/environment.txt"
git show "$baseline_commit:Sources/Core.swift" > "$output/baseline/Core.swift"
git show "$baseline_commit:Tests/main.swift" > "$output/baseline/main.swift"
cp Sources/Core.swift "$output/optimized/Core.swift"
cp "$output/baseline/main.swift" "$output/optimized/main.swift"
# Instrument only read counts, equally in both versions, for the churn workload.
python3 - "$output" <<'PY'
import sys
from pathlib import Path
for variant in ('baseline', 'optimized'):
    root = Path(sys.argv[1])/variant
    source = (root/'Core.swift').read_text()
    signature = 'func readReadyImage(_ url: URL, identity: Identity) -> ReadyImage? {'
    assert signature in source
    (root/'Instrumented.swift').write_text(source.replace(signature,
        'var benchmarkReads = 0\n' + signature + '\n    benchmarkReads += 1'))
PY
for variant in baseline optimized; do
  folder="$output/$variant"
  for name in tests reader idle churn; do
    core="$folder/Core.swift"
    case "$name" in
      tests) main="$folder/main.swift" ;;
      reader) main="Benchmarks/Reader/main.swift" ;;
      idle) main="Benchmarks/Idle/main.swift" ;;
      churn) main="Benchmarks/Churn/main.swift"; core="$folder/Instrumented.swift" ;;
    esac
    xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" \
      -module-cache-path build/ModuleCache "$core" "$main" -o "$folder/$name"
  done
done
for variant in baseline optimized; do
  folder="$output/$variant"
  # time -l may require an unrestricted Terminal session on macOS.
  /usr/bin/time -l "$folder/tests" > "$folder/tests.txt" 2> "$folder/resources.txt"
  cp build/benchmark.json "$folder/benchmark.json"
done
fixtures=$(python3 -c 'import json; print(json.load(open("build/performance/baseline/benchmark.json"))["fixtureDirectory"])')
for variant in baseline optimized; do
  folder="$output/$variant"
  "$folder/reader" "$fixtures" > "$folder/reader.json"
  "$folder/churn" "$fixtures/3840x2160-noise-0.png" > "$folder/churn.json"
  "$folder/idle" > "$folder/idle.json"
done
print -r -- "Results: $output (clipboard availability and measurement boundaries are recorded in each report)."
