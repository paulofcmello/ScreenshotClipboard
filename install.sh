#!/bin/zsh
set -eu
cd "${0:A:h}"
case "${1:-}" in
  --restore) exec python3 scripts/activate-thumbnail.py --restore ;;
  --off) exec python3 scripts/activate-thumbnail.py --off ;;
  # Reuses the existing build so the Screen Recording permission stays valid.
  --on) [[ -x build/active-app/ScreenshotClipboard.app/Contents/MacOS/capture ]] || zsh scripts/build-thumbnail.sh
        exec python3 scripts/activate-thumbnail.py ;;
  # Takes effect on the next screenshot; no rebuild or restart.
  --style) case "${2:-}" in
      apple) defaults write local.screenshot-clipboard PreviewStyle native ;;
      classic) defaults delete local.screenshot-clipboard PreviewStyle 2>/dev/null || true ;;
      '') ;;
      *) print -u2 'Usage: ./install.sh --style [apple | classic]'; exit 1 ;;
    esac
    [[ "$(defaults read local.screenshot-clipboard PreviewStyle 2>/dev/null)" == native ]] \
      && print 'Preview style: apple' || print 'Preview style: classic'
    exit 0 ;;
  --help) print 'Usage: ./install.sh [--restore | --off | --on | --style [apple | classic]]'; exit 0 ;;
  '') ;;
  *) print -u2 'Unknown option. Use --help.'; exit 1 ;;
esac
zsh scripts/build-thumbnail.sh
exec python3 scripts/activate-thumbnail.py
