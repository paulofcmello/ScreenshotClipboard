# Validation on the development Mac

Environment: Apple Silicon, macOS 26.5.1 (25F80), Swift 6.0.3. Latest setup completed on 2026-10-16 local time (2026-10-17 01:29 UTC).

## Build and integration tests

`zsh scripts/setup.sh` built and signed the executable with a macOS 13 deployment target, passed **449 assertions**, installed the background app, and started its LaunchAgent.

The integration suite used a **real isolated named NSPasteboard**. It verified exact PNG bytes, TIFF availability, AppKit image readback, real kernel filesystem notifications, partial file writes, delayed metadata, CRC failures, atomic renames, unrelated files, localized names, rapid captures, out-of-order completion, symlinks, duplicate events, and preservation of a newer clipboard generation. The general clipboard was never accessed or changed by the tests. Generated fixtures stayed in a separate temporary folder.

Earlier restricted sessions used an explicitly labeled in-memory clipboard substitute and could not install into Application Support. The latest unrestricted run verified both installation and real pasteboard access.

## Measured filesystem-to-pasteboard latency

| PNG dimensions | Samples | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| 1920 × 1080 | 30 | 19.38 ms | 21.12 ms | 21.42 ms |
| 3840 × 2160 | 20 | 78.29 ms | 79.87 ms | 80.84 ms |
| 3840 × 2160, noisy pixels | 10 | 141.10 ms | 165.17 ms | 165.17 ms |

Timing starts after the synchronous fixture writer closes the PNG and finishes its screenshot metadata, ending after real pasteboard publication. All 60 samples were under 200 ms. These measurements exercise tagged fixtures and image preparation/transfer; they do not establish keyboard-shortcut-to-clipboard latency or guarantee timing under other loads, image sizes, or storage conditions.

The test suite regenerates `build/benchmark.json` with full timings and all samples on every run. Build products, machine-specific reports, and generated image fixtures are excluded from Git.

## Installation verification

- Installed app: `~/Library/Application Support/ScreenshotClipboard/ScreenshotClipboard.app`.
- App signature passed `codesign --verify --deep --strict`.
- LaunchAgent plist passed `plutil -lint`.
- `gui/501/local.screenshot-clipboard` was enabled and running, with one launch and no exits at verification.
- Open file descriptors confirmed that the installed process was watching Desktop and the preferences directory.
- `~/Library/Application Support/ScreenshotClipboard/error.log` existed and was empty.
- Native screenshot settings were `target=file`, `type=png`, and `location=~/Desktop`. The installer backed up the previous settings (including `target=clipboard`).

## Remaining manual verification

The optional native capture benchmark was skipped because `CGPreflightScreenCaptureAccess()` returned false. No Screen Recording permission was requested; the background utility itself does not require it.

Verify the actual full-screen, region, and window shortcuts, pasting into a third-party app, two rapid captures, multiple monitors if available, unrelated PNG exclusion, any Desktop permission prompts, and startup after logout/login. See [README.md](README.md) for the steps. The native floating thumbnail may delay file creation before this utility sees the screenshot.

## Repository portability check

The installer and documentation update was verified using a local Git clone with the updated files copied into it, in a temporary folder whose name contains spaces. The copy started without a `build/` directory or compiler cache. Build and test scripts were invoked from outside the checkout; compilation, executable help, code-signature verification, and all **449 assertions** passed.

This portability run took place in a restricted session and used the suite's explicitly labeled in-memory clipboard substitute. It does not add a new real-pasteboard or installed-agent verification to the unrestricted results above. Installation was not repeated during this check.

All shell scripts passed syntax checks. The top-level installer's help and unknown-option handling ran without building or installing. Environment checks passed on this Mac, and simulated unsupported-OS, pre-macOS-13, and missing-compiler cases returned actionable errors. Relative documentation links were checked locally.

## Performance-audit update installation

The performance and reliability update was rebuilt, reinstalled and restarted at the user’s request. All **1,108 assertions** passed with a real isolated named NSPasteboard; native screen capture was skipped because permission was not already granted. Launchd reported the updated service running and the custom screenshot save folder was retained. See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) for the matched before/after measurements and [installation test results](docs/performance-results/installed-regressions.json) for this later validation run.
