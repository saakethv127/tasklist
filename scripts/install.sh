#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p "$HOME/Applications"
if pgrep -x Tasklist >/dev/null; then
    printf 'Quit Tasklist before installing an updated build.\n' >&2
    exit 1
fi
ditto dist/Tasklist.app "$HOME/Applications/Tasklist.app"
open "$HOME/Applications/Tasklist.app" --args "$@"
