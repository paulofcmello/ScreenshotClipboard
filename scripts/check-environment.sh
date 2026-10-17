#!/bin/zsh
set -eu

if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 -- "ScreenshotClipboard requires macOS 13 or newer. Linux and Windows are not supported."
  exit 1
fi

macos_version="$(sw_vers -productVersion)"
if (( ${macos_version%%.*} < 13 )); then
  print -u2 -- "ScreenshotClipboard requires macOS 13 or newer (found ${macos_version})."
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  print -u2 -- "Apple's Swift compiler was not found. In Terminal, run: xcode-select --install"
  print -u2 -- "Finish installing the Command Line Tools, then run this command again."
  exit 1
fi
