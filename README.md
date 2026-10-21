# ScreenshotClipboard

Take a screenshot on your Mac and it's already on your clipboard. Just paste.

It saves the file like normal and shows a small preview in the corner.

## Download

1. Download **[ScreenshotClipboard.dmg](https://github.com/paulofcmello/ScreenshotClipboard/releases/latest/download/ScreenshotClipboard.dmg)**.
2. Open it and drag **Screenshot Clipboard** into **Applications**.
3. Open **Screenshot Clipboard** from Applications.

The first time, macOS says it can't verify the app, because it isn't from a paid Apple developer account. Allow it once, either way:

**Option 1: System Settings**

- Click **Done**, not Move to Trash.
- Right away, go to **System Settings → Privacy & Security** and scroll to the bottom.
- Click **Open Anyway** next to "Screenshot Clipboard", enter your password, then click **Open Anyway** again.

The button only appears for about an hour after you try to open the app.

**Option 2: Terminal**

```sh
xattr -dr com.apple.quarantine "/Applications/Screenshot Clipboard.app"
```

This removes the "downloaded from the internet" mark from this app only. Then open it normally.

The app turns itself on. Take a screenshot, and when macOS asks, allow **ScreenshotClipboard** in **Screen & System Audio Recording**.

Works on macOS 13 or newer, on Apple Silicon and Intel Macs.

## Use

| Keys | What it does |
|---|---|
| ⌘⇧4 | Screenshot an area (press Space for a window) |
| ⌘⇧3 | Screenshot the whole screen |
| ⌘V | Paste the image |

The preview:

- **Drag** it into an app to drop the file.
- **Double-click** it to open the file.
- **Right-click** it for Open, Show in Finder, Move to Trash and Close.
- **Swipe or drag it right** to dismiss it.

It also closes by itself after 5 seconds. ⌘⇧5 still opens Apple's own screenshot tool.

## Settings

Open **Screenshot Clipboard** to turn it on or off and pick the preview look (Apple or Classic). The window only runs while it's open; screenshots keep working after you close it.

Turning it off gives ⌘⇧3 and ⌘⇧4 back to macOS.

## Update

Download the new DMG and drag the app into Applications again, replacing the old one. Then open it once.

## Uninstall

Open the app and turn it off, then move **Screenshot Clipboard** from Applications to the Trash.

## Build from source

Needs Apple's command line tools (`xcode-select --install`).

```sh
git clone https://github.com/paulofcmello/ScreenshotClipboard.git
cd ScreenshotClipboard
./install.sh                   # build and install to Applications
./install.sh --off             # turn it off
./install.sh --on              # turn it on
./install.sh --style apple     # or: classic
```

## Notes

- It runs in the background with no Dock or menu bar icon, and nothing is uploaded.
- Screenshots go to your usual screenshot folder as PNG files.

Code is in `Sources/`; [performance notes](PERFORMANCE_AUDIT.md) and [older version](LEGACY.md) are kept for reference.
