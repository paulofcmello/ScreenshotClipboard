# ScreenshotClipboard

Take a screenshot on your Mac and it's already on your clipboard. Just paste.

It saves the file like normal and shows a small preview in the corner.

## Install

You need macOS, Python 3 and Apple's command line tools. Install the tools with `xcode-select --install` if you don't have them.

```sh
git clone https://github.com/paulofcmello/ScreenshotClipboard.git
cd ScreenshotClipboard
./install.sh
```

Then take a screenshot. When macOS asks, allow **ScreenshotClipboard** in
**System Settings → Privacy & Security → Screen & System Audio Recording**.

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

## Commands

Run these from the `ScreenshotClipboard` folder.

```sh
./install.sh --off             # turn it off and give ⌘⇧3/4 back to macOS
./install.sh --on              # turn it back on
./install.sh --style apple     # preview looks like Apple's thumbnail
./install.sh --style classic   # original preview look
./install.sh --restore         # go back to the version before the preview
```

## Update

```sh
git pull
./install.sh
```

After an update, macOS may ask for Screen Recording permission again. If it keeps asking, remove ScreenshotClipboard from the Screen Recording list, allow it again and run `./install.sh --on`.

## Notes

- It only runs in the background, with no Dock or menu bar icon, and nothing is uploaded.
- Screenshots go to your usual screenshot folder as PNG files.
- Tested on Apple Silicon with macOS 26.5.

Code is in `Sources/`; [performance notes](PERFORMANCE_AUDIT.md) and [older version](LEGACY.md) are kept for reference.
