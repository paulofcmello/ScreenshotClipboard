# Performance

Measured on Apple Silicon, macOS 26.5. "Footprint" is what Activity Monitor shows as "Memory". "Resident" also counts memory shared with the system, so it reads higher.

## vs Apple's screenshot thumbnail

Same test for both: ⌘⇧3 pressed three times (full screen, 2940×1912), from keypress until the preview closes. Every process involved was counted: `screencapture` plus `screencaptureui` for Apple; `screencapture`, the preview process and the shortcut listener for ours. Both sides were measured the same way, by sampling `ps` every 20 ms.

| | Apple | ScreenshotClipboard | Change |
|---|---:|---:|---:|
| CPU time per screenshot | 0.22 s | 0.29 s | **+34%** |
| Peak memory (resident) | 53.2 MB | 41.9 MB | **−21%** |
| Peak memory (footprint, 1080p test) | 20.9 MiB | 13.0 MiB | **−38%** |
| Time processes stay alive, 3 screenshots | 24.5 s | 18.6 s | −24% |
| Copies the image to the clipboard | no | yes | — |

Ours uses more CPU because it starts a fresh preview process for every screenshot and also writes the image to the clipboard. Apple keeps one `screencaptureui` process running across captures. In exchange, ours uses less memory and quits as soon as each preview closes.

## What it costs that Apple doesn't

| | Value |
|---|---:|
| Background shortcut listener, idle memory | 6.4 MiB |
| Background shortcut listener, idle CPU | ~0% (no polling) |
| Capture itself (`screencapture`, 4K) | 0.48 s, 5.2 MiB peak |

Apple's thumbnail process isn't running when idle, so the ~6 MiB listener is the one constant cost. The preview process quits as soon as the preview closes.

## Preview styles

The same full-size 2940×1912 screenshot, two runs each:

| | Peak memory | CPU time |
|---|---:|---:|
| Classic | 13.7 MiB | 0.10–0.19 s |
| Apple-like | 12.8–12.9 MiB | 0.13–0.14 s |

The Apple-like style is slightly lighter because its thumbnail is smaller. The CPU difference is within run-to-run noise.

## Limits

- Small samples (2–3 runs or 3 screenshots per number) on one machine. Treat differences under ~10% as noise.
- WindowServer and clipboard-service memory aren't included, since macOS doesn't expose them without root.
- No battery measurement.

Raw data is in [docs/performance-results](docs/performance-results/) and [Prototypes/Thumbnail](Prototypes/Thumbnail/).
