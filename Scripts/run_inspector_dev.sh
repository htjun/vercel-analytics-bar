#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSPECTOR_ROOT="$REPOSITORY_ROOT/Tools/ChartInspector"
INSPECTOR_URL="http://127.0.0.1:5173/"
DEV_SERVER_PID=""

cleanup() {
    if [[ -n "$DEV_SERVER_PID" ]] && kill -0 "$DEV_SERVER_PID" 2>/dev/null; then
        kill -TERM "$DEV_SERVER_PID" 2>/dev/null || true
        wait "$DEV_SERVER_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

npm --prefix "$INSPECTOR_ROOT" run dev &
DEV_SERVER_PID=$!

for _ in {1..100}; do
    if ! kill -0 "$DEV_SERVER_PID" 2>/dev/null; then
        wait "$DEV_SERVER_PID"
    fi

    if curl --silent --fail --max-time 1 "$INSPECTOR_URL" >/dev/null; then
        break
    fi

    sleep 0.1
done

if ! curl --silent --fail --max-time 1 "$INSPECTOR_URL" >/dev/null; then
    echo "Chart Inspector development server did not become ready at $INSPECTOR_URL." >&2
    exit 1
fi

"$REPOSITORY_ROOT/Scripts/run_debug.sh" --chart-inspector-dev-server

echo "Chart Inspector is running with hot reload. Press Ctrl-C to stop the development server."
wait "$DEV_SERVER_PID"
