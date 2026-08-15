#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: $0 /absolute/path/to/application-executable" >&2
    exit 64
fi

TARGET_EXECUTABLE=$1
PIDS=()

while read -r pid command; do
    case "$command" in
        "$TARGET_EXECUTABLE" | "$TARGET_EXECUTABLE "*)
            PIDS+=("$pid")
            ;;
    esac
done < <(ps -axo pid=,command=)

if [[ ${#PIDS[@]} -eq 0 ]]; then
    exit 0
fi

kill -TERM "${PIDS[@]}" 2>/dev/null || true

for _ in {1..30}; do
    remaining=()
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            remaining+=("$pid")
        fi
    done
    if [[ ${#remaining[@]} -eq 0 ]]; then
        exit 0
    fi
    PIDS=("${remaining[@]}")
    sleep 0.1
done

echo "Analytics Menu Bar did not quit normally; force-stopping PID(s): ${PIDS[*]}" >&2
kill -KILL "${PIDS[@]}" 2>/dev/null || true
