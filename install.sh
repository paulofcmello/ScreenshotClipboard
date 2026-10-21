#!/bin/zsh
set -eu
cd "${0:A:h}"
case "${1:-}" in
  --restore) exec python3 scripts/activate-thumbnail.py --restore ;;
  --help) print 'Usage: ./install.sh [--restore]'; exit 0 ;;
  '') ;;
  *) print -u2 'Unknown option. Use --help.'; exit 1 ;;
esac
zsh scripts/build-thumbnail.sh
exec python3 scripts/activate-thumbnail.py
