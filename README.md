# ScreenshotClipboard

A small native macOS background utility. Keep using **⌘⇧3**, **⌘⇧4**, and **⌘⇧4, Space**: macOS saves the screenshot normally; this utility copies the completed image so you can paste it with **⌘V**.

No shortcut interception, Accessibility permission, screen capture API, network access, third-party runtime, menu bar icon, or Dock icon. Requires macOS 13 or newer and Apple's Command Line Tools to build. Tested with Swift 6.0.3 on Apple Silicon / macOS 26.5.1.

The installed utility is a background `.app` bundle. A per-user LaunchAgent starts it immediately and whenever you log in; there is no app window to keep open.

## Install on this Mac

Run this in **Terminal** under your usual login (no sudo):

```sh
git clone https://github.com/paulofcmello/ScreenshotClipboard.git
cd ScreenshotClipboard
zsh scripts/setup.sh
```

This builds and signs the utility, runs verification using a separate test clipboard, installs an agent, and starts it immediately and after login. Your current general clipboard is not used by the automated tests. Setup sets native screenshot output to **PNG files on Desktop**, backing up the previous target, format, and location. On this Mac the original target was `clipboard`, which would prevent a file watcher from seeing captures. It briefly restarts SystemUIServer to refresh screenshot preferences.

If you want to retain your current custom screenshot folder instead of switching to Desktop:

```sh
zsh scripts/setup.sh --keep-location
```

This option preserves the configured folder, so files will be saved there rather than Desktop. The utility watches both Desktop and the configured folder. Ordinary install fulfills the Desktop requirement. Do not choose **Clipboard**, Mail, or another app as the native capture destination: macOS must produce a file.

Installation creates:

- `~/Library/Application Support/ScreenshotClipboard/ScreenshotClipboard.app`
- `~/Library/Application Support/ScreenshotClipboard/screenshot-preferences.plist` (original settings)
- `~/Library/Application Support/ScreenshotClipboard/applied-preferences.plist`
- `~/Library/Application Support/ScreenshotClipboard/error.log`
- `~/Library/LaunchAgents/local.screenshot-clipboard.plist`

If macOS requests Desktop access, allow it. Check **System Settings → Privacy & Security → Files and Folders** if access is denied. A new custom folder can require access too. Full Disk Access is not normally needed. The utility does not request Screen Recording or Accessibility. macOS may separately control clipboard access; allow access if macOS presents that setting.

Restricted coding sessions may be unable to access the pasteboard service or install into your Library. If that happens, run setup in Terminal. Installation and real isolated pasteboard access were verified on the development Mac. See [VALIDATION.md](VALIDATION.md) for measured results and their limits.

## Verify normal use

1. Press **⌘⇧3**. Wait for the native floating thumbnail to disappear and the PNG to appear on Desktop, then paste into Notes or a message draft.
2. Repeat with **⌘⇧4** (region) and **⌘⇧4, Space** (window). Confirm that the PNG remains on Desktop and the pasted item is an image.
3. Take two quick screenshots; the clipboard should contain the latest completed capture. With multiple monitors, macOS produces separate files; the clipboard ends up with the latest capture file, not a stitched image or history of all displays.
4. Copy some text, then save or drag an ordinary PNG (such as an exported drawing) onto Desktop. Pasting should still produce your text. Only newly created images marked as screenshots should replace the clipboard. Files present at startup are never copied.
5. Log out and back in, then repeat. Check status with the command below.

The floating thumbnail can delay the file save for several seconds. This is native behavior and is preserved. Clipboard latency is measured **after the saved image is complete**, not from pressing the shortcut. For earlier file creation, optionally turn off **Show Floating Thumbnail** in **⌘⇧5 → Options**. On macOS Tahoe, choose **SDR (Most Compatible)** if HDR capture would produce HEIF files; this utility intentionally accepts PNG only.

## Controls

From this project directory:

```sh
./build/screenshot-clipboard --status
./build/screenshot-clipboard --disable
./build/screenshot-clipboard --enable
./build/screenshot-clipboard --uninstall
```

Disable persists across login. It leaves normal screenshot saving enabled. Uninstall stops the agent, removes only the utility's app/configuration/log, and restores original screenshot settings **only where they still match values set by the installer**. It does not delete screenshots, touch image folders, change your clipboard, or delete the project. The empty support folder may remain. These commands also work using the installed executable:

```sh
"$HOME/Library/Application Support/ScreenshotClipboard/ScreenshotClipboard.app/Contents/MacOS/screenshot-clipboard" --disable
```

No executable bit is needed on the `.sh` files when run with `zsh` as shown.

## Architecture and guarantees

`DispatchSource` uses macOS vnode notifications (kqueue) for directory creation/rename events and per-candidate write/extend/attribute events. There is no screenshot polling, FSEvents batching, readiness sleep, Spotlight indexing dependency, or shortcut replacement. New files are checked immediately. Incomplete files are checked again only when the filesystem reports a change. A single one-shot cleanup task releases unused candidate descriptors after approximately 30–60 seconds; it never delays copying. At most 128 candidates are watched concurrently.

Recognition requires the binary plist extended attribute `com.apple.metadata:kMDItemIsScreenCapture` to be true. Filenames and system language do not matter. Existing files, old files moved into the folder, symlinks, ordinary PNGs, and corrupt/incomplete PNGs are ignored. A screenshot copied by another app can retain this metadata; a newly created copy with fresh timestamps cannot always be distinguished from a native capture without observing the capture process. This utility deliberately avoids that extra access.

Before publication, the utility reads an immutable snapshot through a file descriptor, verifies PNG framing and every chunk CRC through Apple's system zlib, requires the terminal IEND chunk, eagerly decodes through ImageIO, prepares PNG and TIFF image representations, and checks file identity, size, modification time, and change time again. A concurrent change rejects the snapshot. Original PNG bytes (including Retina pixels, alpha, DPI and color metadata) are placed on `NSPasteboard`, plus TIFF for broader app support. No path/file URL is placed on the clipboard. Files are never modified by the watcher.

Captures are handled on one serial main queue. A newer capture cannot be replaced by an older candidate that finishes late. Every successful capture replaces the previous clipboard image, as with normal screenshot copying; multi-monitor files are handled individually and the last one wins. There is no screenshot history.

The watcher observes pasteboard `changeCount` when a candidate is discovered and before publication. If another app changes the clipboard while that candidate is being prepared, the candidate is skipped to preserve the newer content. It cannot observe a change that occurs before the file's first event. AppKit provides no atomic compare-and-swap transaction across applications, so a tiny final check-to-write race is unavoidable. PNG completeness is established from the format and stable snapshot, not an unreliable assumption that a create event means the writer has closed.

The screenshot preference plist directory is also monitored for location changes; **SIGHUP** reloads the location explicitly. If a watched folder is removed/renamed, the process exits and launchd retries with a 10-second throttle. Restore a missing folder or choose a valid save location. Only events cause work while idle. Image decoding and TIFF generation use transient memory proportional to screenshot dimensions. Very large captures, heavy system load, delayed metadata, or slow/network/cloud-backed save folders can exceed 200 ms; this is a best-effort target, not a real-time scheduling guarantee.

## Tests and latency measurements

```sh
zsh scripts/build.sh
zsh scripts/test.sh
```

Tests create their own temporary folder and named pasteboard. They verify PNG integrity, exact image bytes, TIFF availability, AppKit image reading, baseline exclusion, unrelated PNG exclusion, localized filenames, partial writes, delayed metadata, atomic rename, clipboard conflicts, out-of-order completion, rapid captures, symlinks, and duplicate notifications. Generated fixtures are retained in the printed temporary folder for inspection, never mixed with your screenshots. The operating system can eventually clean its temporary folder.

The benchmark writes tagged 1080p and 4K PNGs, including a 4K noisy image, closes the file and finishes screenshot metadata, then measures until image publication. This exercises actual kernel filesystem events and image preparation. With pasteboard access, it uses a real named `NSPasteboard`; otherwise it clearly labels an in-memory substitute and **does not claim real clipboard timing**. Results and all samples are saved to `build/benchmark.json`.

If Screen Recording permission is **already granted** to the test host, five additional `screencapture` samples run without asking for permission. These copy to the isolated test board. Their process-exit-to-publication measurements are lower-bound proxies because the capture subprocess can exit after writing finishes; they are not exact completion latency. The utility itself never captures the screen.

To inspect live production timing, first disable the agent, then run one foreground instance:

```sh
./build/screenshot-clipboard --disable
./build/screenshot-clipboard --metrics
```

Take native screenshots. Each `copied` JSON record reports `processingMs` and `mtimeToClipboardMs`. The latter includes the interval after the last file data modification, filesystem delivery, metadata availability, validation, and pasteboard submission. Modification time is an approximation of write completion, not an exact writer-close timestamp. It is useful as a conservative proxy on local APFS with unchanged timestamps. Stop with **Control+C**, then restore background operation:

```sh
./build/screenshot-clipboard --enable
```

Errors appear in `~/Library/Application Support/ScreenshotClipboard/error.log`. Normal background operation records no screenshots, filenames, or image contents and does not accumulate timing logs.

## Research

Apple documents file saving and clipboard capture as alternative native destinations, with the Control modifier selecting the clipboard: [Take a screenshot on Mac](https://support.apple.com/en-ie/102646). Apple's [Dispatch filesystem events](https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent) provide write, extend, attribute, and rename notifications. [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) provides native image transfer; [ImageIO status](https://developer.apple.com/documentation/imageio/cgimagesourcegetstatus(_:)) complements explicit PNG integrity validation.

The [clipboard-screenshot repository](https://github.com/stevederico/clipboard-screenshot) demonstrates the same file-watcher approach using shell/AppleScript. This implementation uses a persistent Swift process to avoid per-capture subprocess startup and sleep delays. [REA](https://github.com/rea-tools/rea) is a reverse-engineering toolkit; no reverse engineering or additional runtime is needed for these public macOS APIs. No code was copied from either project.
