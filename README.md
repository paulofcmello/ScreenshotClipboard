# ScreenshotClipboard

**Save screenshots as files and copy them to the clipboard automatically.**

Keep using **⌘⇧3** (full screen), **⌘⇧4** (region), and **⌘⇧4, Space** (window). macOS saves the screenshot; ScreenshotClipboard copies the completed image so you can paste it with **⌘V**. Your screenshot files stay where they are.

This is a small native Swift background app with no window, Dock icon, or menu bar icon. It starts after login, works locally, and does not upload images or keep a clipboard history. It uses filesystem events rather than polling and does not intercept shortcuts.

## Requirements

- **macOS 13 or newer.** Linux and Windows are not supported.
- **Apple's Command Line Tools**, including Git and the Swift compiler. Full Xcode also works; Homebrew and third-party packages are not required.
- A normal logged-in macOS desktop session. Install as your usual user, **without `sudo`**.

If the Command Line Tools are missing, open **Terminal** and run:

```sh
xcode-select --install
```

Finish the installation dialog before continuing. You can check the selected compiler with `xcrun swiftc --version`. The project builds for the current Mac's architecture; the verified environment is Apple Silicon with Swift 6.0.3 on macOS 26.5.1. Intel and older supported macOS versions have not been verified. See [validation results](VALIDATION.md).

## Clone and install

Run in **Terminal**:

```sh
git clone https://github.com/paulofcmello/ScreenshotClipboard.git
cd ScreenshotClipboard
./install.sh
```

If the repository is private, GitHub access is required to clone it. No GitHub login is needed for a public repository. You can also download and extract the repository ZIP, open Terminal in the extracted folder, and run `zsh install.sh`. The installer resolves paths relative to itself, so the checkout can live in any folder, including one with spaces.

The installer:

1. Builds the executable locally and applies an ad-hoc code signature; no developer account is needed.
2. Runs the integration tests using a separate test clipboard, preserving your general clipboard.
3. Backs up the original screenshot destination, image format, and save folder.
4. Selects saved PNG output when necessary, preserving your existing save folder.
5. Installs a background app and per-user LaunchAgent, then starts it immediately and after login.

It restarts SystemUIServer only when screenshot preferences actually change. It leaves the native floating thumbnail setting as you configured it. `zsh scripts/setup.sh` remains an equivalent installation command; `./install.sh --help` shows the installer options.

To explicitly change the save folder to **Desktop**, use:

```sh
./install.sh --desktop
```

Use this option only to change the save folder to Desktop. Without it, the configured folder is preserved (`--keep-location` remains a compatible no-op). The app watches Desktop and the configured folder. The folder must exist and be readable. In **⌘⇧5 → Options**, keep a file save destination selected: **Clipboard**, Mail, and other app destinations do not produce the files this utility needs.

## Permissions and first use

Allow **Desktop** access if macOS prompts. If access was denied, check **System Settings → Privacy & Security → Files and Folders** for ScreenshotClipboard or the process macOS names in its prompt. A custom save folder can require access too. If macOS prompts for clipboard access, allow it.

The background utility does not require Accessibility or Screen Recording access. Full Disk Access is not normally needed. Tests optionally exercise native screen capture only if the test host already has Screen Recording permission; they never request it.

After installation:

1. Press **⌘⇧4** and select a region.
2. Wait for the floating thumbnail to disappear and the PNG file to appear on Desktop (or your retained save folder).
3. Paste into Notes or a message draft with **⌘V**. You should get an image, and the saved PNG should remain in the folder.

Repeat with the full-screen and window shortcuts. Two quick screenshots should leave the latest completed capture on the clipboard. An ordinary PNG added to the folder should leave your clipboard alone. Existing files are ignored when the app starts. After your next logout/login, repeat the test to confirm automatic startup.

The floating thumbnail can delay saving for several seconds. For earlier file creation, optionally turn off **Show Floating Thumbnail** in **⌘⇧5 → Options**. Copying starts after macOS saves the image. On macOS Tahoe, use **SDR (Most Compatible)** if HDR capture would produce HEIF files; this utility accepts PNG only.

## Status, pause, and removal

From the checkout, run the command you need:

| Command | Effect |
| --- | --- |
| `./build/screenshot-clipboard --status` | Show launchd status and the configured watched folders. Look for `state = running`. |
| `./build/screenshot-clipboard --disable` | Stop automatic copying, including after login. |
| `./build/screenshot-clipboard --enable` | Resume copying and automatic startup. |
| `./build/screenshot-clipboard --uninstall` | Stop and remove the installed app and agent, and restore owned screenshot settings where possible. |

Pausing leaves screenshot file saving enabled. Uninstall restores a screenshot preference only if it still matches the value the installer set, preserving later changes you made. It does not delete screenshots or the checkout, or change the clipboard. The empty support folder may remain.

The installed app is independent of the checkout: you can move or delete the cloned folder after setup. To use a control command without the checkout, invoke the installed executable, for example:

```sh
"$HOME/Library/Application Support/ScreenshotClipboard/ScreenshotClipboard.app/Contents/MacOS/screenshot-clipboard" --status
```

Replace `--status` with `--disable`, `--enable`, or `--uninstall` as needed.

## Update

From your existing checkout:

```sh
git pull --ff-only
./install.sh --keep-location
```

This rebuilds, tests, replaces the installed app, and restarts the agent. It preserves the existing screenshot save folder and the original preference backup. Use `./install.sh --desktop` if you want to reset the save folder to Desktop. Reinstalling enables the agent even if you previously paused it. If you deleted the checkout, clone it again and use the same installation command.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `git` or `swiftc` is unavailable, or `xcrun` reports a missing tool | Run `xcode-select --install`, complete installation, and retry. The installer checks for macOS 13+ and a selected Swift compiler before building. |
| `Permission denied` when running `./install.sh` | Use `zsh install.sh`; it does not require the executable bit to be preserved. |
| Cannot save inside `~/Library/Application Support`, or clipboard service unavailable in a coding session | Run setup directly in macOS Terminal under your normal login. A restricted agent sandbox can block Library writes and desktop services independently of macOS privacy permissions. `sudo` is not the fix. |
| `Repository not found` when cloning | Check the repository URL and your GitHub access if it is private. If GitHub itself cannot be reached, check the network connection. |
| Screenshots copy only after several seconds | Wait for the native floating thumbnail to disappear, or disable it in screenshot Options. The app cannot copy a file before macOS saves it. |
| Screenshots never copy | Confirm PNG output, a file save destination, folder access, and a running agent. Check the log below. HEIF/JPEG and clipboard-only capture are not supported. |
| Agent keeps exiting | Restore any removed or renamed watched folder, or choose an existing save folder. launchd retries with a 10-second throttle. |
| `--status` says the service was not found | The agent may be paused or not installed. Run `--enable` after a successful install, or rerun the installer. The status command can exit successfully even when launchd reports a missing service; read its output. |

Read recent errors with:

```sh
tail -n 50 "$HOME/Library/Application Support/ScreenshotClipboard/error.log"
```

Normal background operation does not accumulate timing logs or record screenshot filenames or image contents. If you need help, include your macOS and Swift versions, the installer or status output, and relevant error log lines in a [GitHub issue](https://github.com/paulofcmello/ScreenshotClipboard/issues).

## Installed files

All installed components belong to your user account:

| Path | Purpose |
| --- | --- |
| `~/Library/Application Support/ScreenshotClipboard/ScreenshotClipboard.app` | Background executable and app metadata. |
| `~/Library/Application Support/ScreenshotClipboard/screenshot-preferences.plist` | Original screenshot preferences for uninstall. |
| `~/Library/Application Support/ScreenshotClipboard/applied-preferences.plist` | Preferences owned by the installer. |
| `~/Library/Application Support/ScreenshotClipboard/error.log` | Agent errors. |
| `~/Library/LaunchAgents/local.screenshot-clipboard.plist` | Per-user login and restart configuration. |

## Development and testing

Build and test without installing or changing screenshot preferences:

```sh
zsh scripts/build.sh
zsh scripts/test.sh
```

The suite covers PNG integrity, exact image bytes, TIFF availability, AppKit image readback, real filesystem events, existing-file exclusion, unrelated images, localized filenames, partial writes, delayed metadata, atomic renames, clipboard conflicts, out-of-order completion, rapid captures, symlinks, and duplicate events. Tests create fixtures in a separate temporary folder and print its path. The operating system can eventually clean that folder.

Benchmarks write 1080p and 4K tagged fixtures and save results to `build/benchmark.json`. When macOS pasteboard services are available, tests use a real isolated named pasteboard. Otherwise they clearly report an in-memory substitute; those timings exclude clipboard transfer. Build outputs, compiler caches, and benchmark results stay under ignored `build/` and are regenerated locally; a clone does not depend on them.

The optional native capture benchmark, when already authorized, uses the test screen and writes only to the isolated test clipboard. Its process-exit-to-publication timing is a lower-bound proxy, not exact screenshot completion latency. The normal installed app does not capture the screen itself.

See [VALIDATION.md](VALIDATION.md) for the development Mac's measured results and outstanding manual checks. See [Architecture and measurement](docs/ARCHITECTURE.md) for event handling, screenshot recognition, image validation, clipboard race limits, live timing commands, and references.

## Performance and reliability improvements

- Unrelated directory events no longer reread unchanged pending screenshots. In the controlled 1,000-scan workload, read attempts fell from 1,000 to zero and elapsed time fell from 3,668 ms to 42 ms.
- Completed captures release their candidate slots immediately and are processed in birth order. Regression tests cover 160 consecutive files with reverse-sorted names.
- Clipboard generation checks protect an entire discovered batch when another app copies during decoding. File descriptor identity is checked after opening, and temporary objects are released within each publication.
- Installation preserves the screenshot save folder by default; `--desktop` explicitly selects Desktop. Compatible screenshot settings are left alone, and SystemUIServer restarts only when settings change.
- PNG integrity checks, eager decoding, and eager PNG/TIFF publication remain intact. Direct TIFF encoding and memory mapping were investigated but not adopted because the full-path benefit or correctness tradeoff did not justify them.

Normal capture latency showed mixed before/after results, with no demonstrated general speedup or peak-memory reduction. Idle operation was already efficient: both full-daemon runs recorded one interrupt wakeup and zero package-idle wakeups over 30 seconds. See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) for measurement boundaries, raw results, rejected experiments and reproduction commands.

The expanded regression suite passed 1,108 assertions with a real isolated pasteboard during reinstallation. Matched baseline and updated performance runs each passed the original 449 assertions with real isolated pasteboards. To build, test, install the latest checkout and restart the login agent while preserving your save folder:

```sh
./install.sh
```

## Behavior and limits

- The latest completed capture replaces the previous clipboard content; there is no screenshot history.
- Multiple monitors produce individual files. The last capture file copied wins; images are not stitched together.
- New PNGs must carry macOS screenshot metadata. Ordinary images and files present at startup are ignored. A newly created copy retaining screenshot metadata can still be treated as a screenshot.
- The app tries to preserve clipboard content changed by another app while a capture is being prepared. macOS provides no atomic clipboard compare-and-swap, so a small final race remains.
- The measured sub-200 ms results apply after fixture saving completes, on the tested Mac. Large images, heavy load, or network/cloud-backed folders can take longer. Native thumbnail delay happens before that interval.

Performance findings, rejected experiments, resource measurements, and reproducible comparisons are documented in [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md).
