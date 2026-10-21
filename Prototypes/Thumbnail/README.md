# Lightweight thumbnail prototype

An isolated, one-shot AppKit experiment. It does not install a service, change screenshot preferences, replace system shortcuts, or modify the existing watcher.

Run from the repository root:

```sh
zsh scripts/thumbnail-prototype.sh
```

Select a region, or press Space to select a window. The prototype saves a PNG in Pictures, publishes PNG bytes and a file URL to the clipboard, then displays a draggable preview for five seconds. Double-click opens the saved file. Dragging copies the file and keeps the preview alive until the drag ends. The process exits after dismissal; saved files and the normal clipboard remain available. Escape cancels capture. Screen Recording permission may be required by macOS.

Use `--full-screen` for the main display or `--output-directory PATH` to choose an existing save directory. These are prototype commands, not replacements for the standard screenshot shortcuts.

## Design

- Uses `/usr/sbin/screencapture -x` without `-u` or `-p`, so the capture goes directly to the requested file without the native floating preview.
- Publishes PNG in a headless phase, then uses `execv` to replace the same process with the preview phase. This releases transfer buffers before AppKit starts drawing. PNG bytes are eagerly stored in the clipboard service and remain available after the process exits. No full-resolution TIFF conversion or continuous capture.
- ImageIO thumbnail capped at 440 pixels; displayed within 220 × 160 points plus a five-point border. The 4K landscape thumbnail's pixel buffer is 436,480 bytes (0.42 MiB).
- Native nonactivating AppKit panel; no web view, animation loop, polling, or global keyboard monitor.
- Original PNG is already on disk. Dragging uses its file URL, not another full-resolution image.
- One-shot timeout; resources released on dismissal. Benchmark mode intentionally stays alive to measure idle CPU before and after the preview.

## Reproduce measurements

```sh
zsh scripts/thumbnail-prototype.sh --make-fixture build/thumbnail-prototype/fixture-4k.png
build/thumbnail-prototype/thumbnail --benchmark \
  --fixture build/thumbnail-prototype/fixture-4k.png \
  --pasteboard local.screenshot-clipboard.prototype-test
```

Add `--no-preview` for the clipboard-only control. Add `--verify-clipboard` for exact PNG-byte and file-URL readback; this adds temporary allocations, so keep it separate from performance runs. Add `--render-preview PATH` for visual inspection, also outside timing runs. Named test clipboards are released when the process exits.

Fixture creation and independent clipboard validation live in `TestSupport.swift`, outside the normal executable. Normal builds omit resource-counter collection and its extra sample timer; `--benchmark`, `--verify-clipboard`, and `--render-preview` select a measurement build in the launcher.

Resource counters come from `proc_pid_rusage`, including physical footprint and resident bytes. CPU ticks are converted using `mach_timebase_info`. `summarize.py` aggregates the saved logs. The existing `Benchmarks/Process/main.swift` measures the current watcher independently.

`TestSupport.swift` is a separate test-only host for a generated 4K image. Its window can be captured with `screencapture -x -o -l WINDOW_ID`, allowing capture-process measurement without recording other apps. The fixture host's memory is not part of prototype measurements. It exits after 30 seconds.

## Scope and remaining checks

PNG/file-URL clipboard publication and capture of the generated test window were exercised. A separate helper validates exact PNG bytes, the file URL, and AppKit image readback after the release executable has exited. Image data was verified byte for byte and preview rendering was inspected. Actual Finder drops, paste behavior in third-party apps, interactive region selection, cancellation, and rapid overlapping captures need manual integration checks before shipping. PNG-only clipboard support is intentional for this prototype; some apps may require a TIFF representation. No production replacement or shortcut integration is installed.

Read the original measurements in [RESULTS.md](RESULTS.md) and the current before/after comparison in [OPTIMIZATION.md](OPTIMIZATION.md). Raw logs and generated fixtures are under `build/thumbnail-prototype/` (ignored by Git).
