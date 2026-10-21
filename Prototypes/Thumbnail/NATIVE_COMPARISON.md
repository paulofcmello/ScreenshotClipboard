# Native Apple screenshot UI comparison — 2026-10-20

Two successful native captures and two prototype runs used the same generated image at **1920 × 1080**. The current test display produced a 1× screenshot; the earlier 3840 × 2160 prototype figures are not the baseline for this comparison.

| Process physical footprint | Apple screencaptureui | Our prototype | Our reduction |
|---|---:|---:|---:|
| Active preview phase | 20.52–20.58 MiB | 12.95–12.99 MiB | about 37% |
| Observed lifetime peak | 20.89 MiB | 13.00–13.03 MiB | about 38% |

These are whole-process footprints, not the isolated cost of thumbnail pixels, nor total system RAM. Apple runs a more capable screenshot interface; our prototype implements a small preview and drag target. This result establishes that our process was not more RAM-demanding in this specific test. It does not establish which consumes less battery or which would win for every screenshot size.

## Method

- A separate test host displayed only a generated image. `screencapture -x -o -l WINDOW_ID` produced a reference PNG. `screencapture -x -o -u -l WINDOW_ID OUTPUT` invoked Apple's native post-capture UI on the same window (the requested output location is ignored for that UI path).
- A separate observer sampled process resource counters approximately every 0.12 seconds. Native active-preview values are medians from seconds 3–6 of each trace; the native capture was invoked at approximately second 2. The second native trace also records the screenshot UI's onscreen overlay by owner PID. This overlay spans the display and persists through cleanup; its bounds alone do not identify the exact thumbnail disappearance time.
- The native UI peaked at 20.89 MiB, fell to about 13 MiB and then 10 MiB during cleanup, and exited roughly 12 seconds after invocation. No native screenshot UI process existed before either successful test.
- Our prototype processed the exact reference PNG using its eager PNG/file-URL clipboard transfer and custom preview. One run used the extended benchmark mode; the second used the ordinary five-second preview lifecycle with diagnostic counters enabled. Both produced approximately 13 MiB peaks. Peak comparisons include both sides of the prototype's `execv` transition; the counters reset at that transition.
- The installed clipboard watcher was temporarily suspended during native captures and resumed in a `finally` block. Generated native files were removed only after their normalized downsample matched the generated reference. No unmatched new files were found. The user's general clipboard was not used for the prototype; named test boards were released on exit.
- Two earlier attempts failed before a native test capture: a missing required output argument and a window-not-yet-rendered race. These were corrected before the two successful measurements and are not included in the comparison.

## CPU and system-service limits

The native screenshot UI accumulated approximately **0.172–0.173 CPU seconds** by its last sample. The first prototype run used **0.14 CPU seconds**, but started from an existing PNG, so it excludes capture work. These are not equivalent end-to-end CPU workloads and should not be turned into a CPU-saving percentage.

The clipboard service stayed around 3.5 MiB in the observed runs; the second prototype trace spanned the whole publication/preview/exit interval and sampled 3.50–3.53 MiB. This does not account for all shared or mapped data. WindowServer resource reads were denied by macOS, and its memory/GPU activity is excluded. We did not elevate to root or change security settings to access it. No battery-energy measurement was made.

## Evidence

Ignored files under `build/native-comparison/` contain the generated reference, test runner and observer sources, `native-1.jsonl`, `native.jsonl` (second run), `prototype.jsonl`, `prototype-2.jsonl`, resource summaries, clipboard-service traces and cleanup records. `cleanup-1.json` and `cleanup.json` each confirm removal of one matching generated screenshot and no unmatched new files. The original installed watcher was verified running afterward.

No production app code or screenshot preference settings were changed for this comparison.
