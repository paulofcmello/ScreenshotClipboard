#!/bin/zsh
set -eu
cd "${0:A:h:h}"
zsh scripts/build.sh
zsh scripts/test.sh
./build/screenshot-clipboard --install "$@"
./build/screenshot-clipboard --status
