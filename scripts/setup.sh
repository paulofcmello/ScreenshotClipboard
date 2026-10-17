#!/bin/zsh
set -eu
cd "${0:A:h:h}"
for argument in "$@"; do
  case "$argument" in
    --keep-location) ;;
    -h|--help)
      print -r -- "Usage: ./install.sh [--keep-location]

Build, test, and install ScreenshotClipboard for your macOS login.
By default, screenshots will be saved as PNG files on Desktop.
--keep-location preserves your current screenshot save folder.

Run in Terminal as your usual user, without sudo.
The app starts immediately and after login. See README.md for controls."
      exit 0
      ;;
    *)
      print -u2 -- "Unknown option: $argument"
      print -u2 -- "Usage: ./install.sh [--keep-location]"
      exit 64
      ;;
  esac
done
if (( EUID == 0 )); then
  print -u2 -- "Run the installer as your usual macOS user, without sudo."
  exit 1
fi
print -- "Building ScreenshotClipboard..."
zsh scripts/build.sh
print -- "Running tests with a separate test clipboard..."
zsh scripts/test.sh
print -- "Installing the background app and login agent..."
./build/screenshot-clipboard --install "$@"
./build/screenshot-clipboard --status
print -- "Setup complete. Take a screenshot, wait for its file to save, then paste with Command-V."
