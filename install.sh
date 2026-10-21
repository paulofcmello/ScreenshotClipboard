#!/bin/zsh
# Build from source and install. Most people should download the DMG from
# GitHub Releases instead; that needs no developer tools.
set -eu
cd "${0:A:h}"
name="Screenshot Clipboard.app"
target=/Applications
[[ -w $target ]] || target=~/Applications
installed="$target/$name"
cli="$installed/Contents/MacOS/settings"

case "${1:-}" in
  --on|--off|--style|--status) exec "$cli" "$@" ;;
  --restore) exec python3 scripts/activate-thumbnail.py --restore ;;
  --help) print 'Usage: ./install.sh [--on | --off | --style [apple | classic] | --status | --restore]'; exit 0 ;;
  '') ;;
  *) print -u2 'Unknown option. Use --help.'; exit 1 ;;
esac

zsh scripts/build-app.sh
mkdir -p "$target"
rm -rf "$installed"
cp -R "build/$name" "$installed"
# Earlier versions put the settings app in ~/Applications.
[[ $target == /Applications ]] && rm -rf ~/Applications/"$name"
"$cli" --on
print "Installed to $installed"
