# ScreenshotClipboard

Save a screenshot, copy it immediately, and show a small draggable preview. The image is on the clipboard before the preview disappears.

- **⌘⇧4**: select a region; press Space for a window.
- **⌘⇧3**: capture the main display.
- **⌘V**: paste the image, or paste its file into Finder.
- Drag the preview to copy the file; double-click it to open it. It closes after five seconds.

A native Swift shortcut listener starts at login. The capture/preview worker runs only when needed and exits after dismissal. There is no polling, Dock icon, menu bar icon, upload, or clipboard history. The listener still uses some memory while idle.

## Install

Requires macOS, Apple's Command Line Tools (`xcode-select --install`), and Python 3. The current version was tested on Apple Silicon with macOS 26.5.1; other systems are unverified.

```sh
git clone https://github.com/paulofcmello/ScreenshotClipboard.git
cd ScreenshotClipboard
./install.sh
```

Run as your normal user, without sudo. The installer builds and signs the app locally, backs up the previous installation and shortcut settings, installs a LaunchAgent, and starts it. It takes over ⌘⇧3/4; ⌘⇧5 and the Control-modified native shortcuts remain Apple's. The configured screenshot folder is preserved and must exist; Desktop is the fallback. Captures are saved as PNG files.

Allow **ScreenshotClipboard** in **System Settings → Privacy & Security → Screen & System Audio Recording** when prompted. Allow access to the save folder if requested. Then take a screenshot and try pasting while its preview remains visible.

## Restore the previous version

```sh
./install.sh --restore
```

The first activation backup is retained in `~/Library/Application Support/ScreenshotClipboard/before-thumbnail`. Restore reinstates that app, its LaunchAgent, and the saved native screenshot shortcut settings. It leaves screenshot files intact.

## Development and measurements

- Build without installing: `zsh scripts/build-thumbnail.sh`.
- Production sources: `Sources/Hotkeys/main.swift` and `Sources/Capture/main.swift`.
- Activation and rollback: `scripts/activate-thumbnail.py`.
- [Prototype measurements](Prototypes/Thumbnail/README.md) include the historical optimization experiments and native comparison. These worker measurements do not include the installed shortcut listener.
- [Legacy watcher documentation](LEGACY.md) describes the previous implementation, retained for reference. Its installation entry point is `zsh scripts/setup.sh`; restore the current shortcut installation before switching to it.

The installed version was verified with a real capture and exact PNG/file-URL clipboard readback after the worker exited. The user also confirmed the shortcut works after granting screen capture permission. The prototype used fixture-only tests that missed a crash in the capture argument construction; production constructs those arguments incrementally.
