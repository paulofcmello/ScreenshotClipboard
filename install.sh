#!/bin/zsh
set -eu
exec zsh "${0:A:h}/scripts/setup.sh" "$@"
