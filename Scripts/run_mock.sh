#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_NAME=${1:-ideal}
FIXTURE_ROOT="$REPOSITORY_ROOT/DemoFixtures"
FIXTURE_PATH="$FIXTURE_ROOT/$FIXTURE_NAME.json"
HOST_ARCHITECTURE=$(uname -m)
DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/MockDerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/VercelAnalyticsBar.app"
RESOURCE_PATH="$APP_PATH/Contents/Resources/DemoFixture.json"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/VercelAnalyticsBar"
LAUNCH_ARGUMENT=""

case ${2:-} in
    "")
        ;;
    --component-editor | --component-editor-dev-server)
        LAUNCH_ARGUMENT=$2
        ;;
    *)
        echo "Unsupported mock launch argument: $2" >&2
        exit 64
        ;;
esac

if [[ ! "$FIXTURE_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid mock fixture name '$FIXTURE_NAME'. Use lowercase letters, numbers, and hyphens." >&2
    exit 1
fi

if [[ ! -f "$FIXTURE_PATH" ]]; then
    echo "Mock fixture '$FIXTURE_NAME' does not exist in DemoFixtures." >&2
    exit 1
fi

"$REPOSITORY_ROOT/Scripts/terminate_app.sh" "$APP_EXECUTABLE"

xcodebuild \
    -project "$REPOSITORY_ROOT/VercelAnalyticsBar.xcodeproj" \
    -scheme VercelAnalyticsBar \
    -configuration Debug \
    -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MOCK_MODE' \
    build

/usr/bin/install -m 0644 "$FIXTURE_PATH" "$RESOURCE_PATH"
if [[ -n "$LAUNCH_ARGUMENT" ]]; then
    open "$APP_PATH" --args "$LAUNCH_ARGUMENT"
else
    open "$APP_PATH"
fi
