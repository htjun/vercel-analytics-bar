#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VIOLATIONS=0

check_file() {
    local file_path=$1
    if [[ ! -f "$file_path" ]]; then
        return 0
    fi

    case "$file_path" in
        *.swift | *.md | *.sh | *.yml | *.yaml | *.xcconfig | *.plist | *.pbxproj | *.xcscheme | *.json)
            ;;
        *)
            return
            ;;
    esac

    if /usr/bin/ruby -e 'exit File.read(ARGV.fetch(0), encoding: "UTF-8").match?(/[\u{AC00}-\u{D7A3}]/) ? 0 : 1' "$file_path"; then
        echo "Korean text is not allowed: $file_path" >&2
        VIOLATIONS=1
    fi
}

if (($# > 0)); then
    for file_path in "$@"; do
        check_file "$file_path"
    done
else
    cd "$REPOSITORY_ROOT"
    while IFS= read -r -d '' file_path; do
        check_file "$file_path"
    done < <(git ls-files --cached --others --exclude-standard -z)
fi

exit "$VIOLATIONS"
