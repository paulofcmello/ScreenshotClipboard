# Performance

Measured on Apple Silicon, macOS 26.5. Memory is the process's physical footprint, which is what Activity Monitor shows as "Memory".

## vs Apple's screenshot thumbnail

Both sides used the same 1920×1080 test image. "Apple" is `screencaptureui`, the process behind the native floating thumbnail.

| | Apple | ScreenshotClipboard | Change |
|---|---:|---:|---:|
| Memory while preview is shown | 20.5 MiB | 13.0 MiB | **−37%** |
| Peak memory | 20.9 MiB | 13.0 MiB | **−38%** |
| CPU time | 0.17 s | 0.14 s | −19%* |
| Process alive after capture | ~12 s | ~5 s | −58% |
| Copies the image to the clipboard | no | yes, ~58 ms after the file is saved (4K) | — |

\*Not an exact comparison: Apple's number includes taking the capture, ours starts from the saved file.

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

- Small samples (2–3 runs per number) on one machine. Treat differences under ~10% as noise.
- WindowServer and clipboard-service memory aren't included, since macOS doesn't expose them without root.
- No battery measurement.

Raw data is in [docs/performance-results](docs/performance-results/) and [Prototypes/Thumbnail](Prototypes/Thumbnail/).
