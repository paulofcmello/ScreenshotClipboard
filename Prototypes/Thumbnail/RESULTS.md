# Original thumbnail prototype measurements — 2026-10-20

These are the initial prototype results. See [OPTIMIZATION.md](OPTIMIZATION.md) for the newer implementation and matched RAM comparison.

The prototype works as an isolated experiment. Its native thumbnail is inexpensive enough to investigate further, but this is not a production replacement or proof that a memory-constrained Mac will never slow down.

## Final build: captured 4K fixture

Input: 3840 × 2160 PNG, 11,717,944 bytes, captured from our own generated test window. Measurements use a separate named clipboard, not the user's clipboard. No clipboard readback or preview screenshot was included in this performance run.

| Measurement | Result |
|---|---:|
| File ready → clipboard publication | 57.7 ms |
| File ready → window ordered onscreen | 307.3 ms |
| Idle physical footprint before preview | 6.14 MiB |
| Footprint with preview settled | 25.55 MiB |
| Lifetime peak physical footprint | 28.63 MiB |
| Highest sampled resident memory | 72.77 MiB |
| Idle CPU before preview, ~10.5 seconds | 0.011% of one core |
| Idle CPU after dismissal, ~10.5 seconds | 0.012% of one core |
| Interrupt wakeups in those idle intervals | 2 / 3 |
| Footprint after dismissal, process deliberately retained | 10.14 MiB |

Normal operation exits after the five-second preview, releasing the process's resources entirely. Benchmark mode deliberately waits before capture and after dismissal to collect idle measurements. Clipboard data remains owned by the clipboard service; these counters do not measure that service's memory or WindowServer allocations. RSS includes shared/file-backed pages and should not be added to footprint as a separate cost.

A copy-only control using the original generated 4K PNG (9,078,464 bytes) settled at 15.17 MiB footprint; two preview runs settled at 23.02–23.09 MiB. Thus the preview added approximately **7.85–7.92 MiB** in those matched fixture runs. They are a small sample, not a statistical guarantee. The initial runs included byte-for-byte clipboard verification in both variants. Their copy times were 38.9–63.2 ms and window-order times 313.9–332.7 ms. The final build additionally bounds portrait preview height and separates optional verification from measurement.

## Capture process, measured separately

`/usr/bin/time -l /usr/sbin/screencapture -x -o -l WINDOW_ID -t png OUTPUT` captured only the generated test window, not other apps:

- Output verified as 3840 × 2160 PNG.
- Wall time: **0.48 seconds**; user CPU: 0.24 s; system CPU: 0.03 s.
- Peak physical footprint: **5.23 MiB**; peak resident memory: **46.52 MiB**.
- The fixture host is test infrastructure and excluded from these counts.

The capture process exits before the prototype reads the file. Its peak and the preview peak therefore are not simultaneous peaks to add together. System capture services can allocate additional memory outside the measured process. Interactive selection time, launch time, screen recording consent, and full-screen captures of real content were not benchmarked. Adding the separately measured capture and publication times suggests roughly **0.54 s**, but that is an estimate, not a measured shortcut-to-clipboard latency. “Shown” measures `orderFrontRegardless` completion, not a compositor-confirmed visible frame.

## Existing watcher comparison

Freshly compiled existing sources, measured with `Benchmarks/Process/main.swift`, normal watch directories and isolated clipboard:

- Idle footprint: **2.73 MiB**.
- Idle CPU over 30 seconds: **0.00020% of one core**.
- One interrupt wakeup.

This is an idle comparison only. We did not compare the old watcher's active full-resolution PNG/TIFF pipeline against the prototype's PNG-only capture path. No claim of equal clipboard compatibility is implied.

## Validation and limitations

- Optimized Swift build passed.
- Final separate validation read back exact original PNG bytes and the matching file URL successfully.
- Rendered preview inspected: complete image, correct aspect ratio, visible border, no clipping.
- Generated window capture completed successfully; output dimensions checked.
- Preview dismissal and normal process exit observed. Benchmark logs contain all idle, visible, dismissal and release phases.
- Finder drop/paste, third-party app paste compatibility, interactive region/window selection, cancellation and overlapping captures remain manual integration checks. They are not claimed as tested.
- No screenshot preferences, standard keyboard shortcuts, installed binary or launch agent were changed.

## Evidence

Raw logs in `build/thumbnail-prototype/`:

- `final-preview.jsonl`: final timing, resident memory, footprint, peak footprint and CPU counters.
- `final-visual.jsonl`, `preview.png`: independent clipboard verification and preview rendering.
- `preview-1.jsonl`, `preview-2.jsonl`, `no-preview.jsonl`: initial matched fixture experiments.
- `capture-resources.txt`, `captured-fixture.png`: generated-window capture measurements and output.
- `watcher-idle.json`: newly compiled watcher comparison.
- `summary.json`: computed results; regenerate with `python3 Prototypes/Thumbnail/summarize.py`.

Build outputs are ignored by Git. Source, benchmark helper and this report live under `Prototypes/Thumbnail/`.
