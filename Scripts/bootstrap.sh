#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to bootstrap development tools." >&2
    exit 1
fi

brew bundle --file="$REPOSITORY_ROOT/Brewfile"
cd "$REPOSITORY_ROOT"
mint bootstrap

echo "Development tools are ready."
