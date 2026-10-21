#!/bin/zsh
set -eu
cd "${0:A:h}"
case "${1:-}" in
  --restore) exec python3 scripts/activate-thumbnail.py --restore ;;
  --off) exec python3 scripts/activate-thumbnail.py --off ;;
  # Reuses the existing build so the Screen Recording permission stays valid.
  --on) [[ -x build/active-app/ScreenshotClipboard.app/Contents/MacOS/capture ]] || zsh scripts/build-thumbnail.sh
        exec python3 scripts/activate-thumbnail.py ;;
  --help) print 'Usage: ./install.sh [--restore | --off | --on]'; exit 0 ;;
  '') ;;
  *) print -u2 'Unknown option. Use --help.'; exit 1 ;;
esac
zsh scripts/build-thumbnail.sh
exec python3 scripts/activate-thumbnail.py
