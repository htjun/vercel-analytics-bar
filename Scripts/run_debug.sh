#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOCAL_CONFIG="$REPOSITORY_ROOT/Config/Local.xcconfig"
HOST_ARCHITECTURE=$(uname -m)
DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/VercelAnalyticsBar.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/VercelAnalyticsBar"
LAUNCH_ARGUMENT=""

case ${1:-} in
    "")
        ;;
    --component-editor | --component-editor-dev-server)
        LAUNCH_ARGUMENT=$1
        ;;
    *)
        echo "Unsupported Debug launch argument: $1" >&2
        exit 64
        ;;
esac

if [[ ! -f "$LOCAL_CONFIG" ]]; then
    echo "Debug launches require an Apple Development signature." >&2
    echo "Copy Config/Local.xcconfig.example to Config/Local.xcconfig and set DEVELOPMENT_TEAM." >&2
    exit 1
fi

BUILD_SETTINGS=$(xcodebuild \
    -project "$REPOSITORY_ROOT/VercelAnalyticsBar.xcodeproj" \
    -scheme VercelAnalyticsBar \
    -configuration Debug \
    -showBuildSettings)
DEVELOPMENT_TEAM=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = //p' <<< "$BUILD_SETTINGS" | tail -n 1)
CODE_SIGN_IDENTITY=$(sed -n 's/^[[:space:]]*CODE_SIGN_IDENTITY = //p' <<< "$BUILD_SETTINGS" | tail -n 1)
PRODUCT_BUNDLE_IDENTIFIER=$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = //p' <<< "$BUILD_SETTINGS" | tail -n 1)

if [[ -z "$DEVELOPMENT_TEAM" || "$DEVELOPMENT_TEAM" == "YOUR_TEAM_ID" ]]; then
    echo "Config/Local.xcconfig must define a valid DEVELOPMENT_TEAM." >&2
    exit 1
fi

if [[ "$CODE_SIGN_IDENTITY" != "Apple Development" ]]; then
    echo "Debug launches require CODE_SIGN_IDENTITY = Apple Development; found '$CODE_SIGN_IDENTITY'." >&2
    exit 1
fi

"$REPOSITORY_ROOT/Scripts/terminate_app.sh" "$APP_EXECUTABLE"

xcodebuild \
    -project "$REPOSITORY_ROOT/VercelAnalyticsBar.xcodeproj" \
    -scheme VercelAnalyticsBar \
    -configuration Debug \
    -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    build

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS=$(codesign -dvv "$APP_PATH" 2>&1)
DESIGNATED_REQUIREMENT=$(codesign -d -r- "$APP_PATH" 2>&1)
SIGNED_ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)

if ! grep -Fq "Authority=Apple Development:" <<< "$SIGNING_DETAILS"; then
    echo "The Debug app was not signed with an Apple Development certificate." >&2
    exit 1
fi

if ! grep -Fq "anchor apple generic" <<< "$DESIGNATED_REQUIREMENT" \
    || grep -Fq "cdhash" <<< "$DESIGNATED_REQUIREMENT"; then
    echo "The Debug app does not have a stable certificate-based designated requirement." >&2
    exit 1
fi

KEYCHAIN_ACCESS_GROUP=$(
    /usr/bin/plutil -extract keychain-access-groups.0 raw -o - - \
        <<< "$SIGNED_ENTITLEMENTS" 2>/dev/null || true
)
EXPECTED_KEYCHAIN_ACCESS_GROUP="$DEVELOPMENT_TEAM.$PRODUCT_BUNDLE_IDENTIFIER"
if [[ "$KEYCHAIN_ACCESS_GROUP" != "$EXPECTED_KEYCHAIN_ACCESS_GROUP" ]]; then
    echo "The Debug app does not have the expected Keychain access group." >&2
    echo "Expected '$EXPECTED_KEYCHAIN_ACCESS_GROUP'; found '${KEYCHAIN_ACCESS_GROUP:-none}'." >&2
    exit 1
fi

if [[ -n "$LAUNCH_ARGUMENT" ]]; then
    open "$APP_PATH" --args "$LAUNCH_ARGUMENT"
else
    open "$APP_PATH"
fi
