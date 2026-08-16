#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="$REPOSITORY_ROOT/VercelAnalyticsBar.xcodeproj"
SCHEME=VercelAnalyticsBar
CONFIGURATION=Release-Direct
LOCAL_CONFIG="$REPOSITORY_ROOT/Config/Local.xcconfig"
ARTIFACT_DIRECTORY="$REPOSITORY_ROOT/.build/ReleaseDirect"
ARCHIVE_PATH="$ARTIFACT_DIRECTORY/VercelAnalyticsBar.xcarchive"
EXPORT_PATH="$ARTIFACT_DIRECTORY/export"
EXPORT_OPTIONS_PATH="$ARTIFACT_DIRECTORY/ExportOptions.plist"
DISK_IMAGE_ROOT="$ARTIFACT_DIRECTORY/disk-image-root"
PUBLISH_DIRECTORY="$ARTIFACT_DIRECTORY/release"
NOTARY_LOG_PATH="$ARTIFACT_DIRECTORY/notarization-log.json"
NOTARYTOOL_PROFILE=${NOTARYTOOL_PROFILE:-AnalyticsMenuBarNotary}
MOUNT_PATH=""

fail() {
    echo "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 is required to create a direct release."
}

build_setting() {
    sed -n "s/^[[:space:]]*$1 = //p" <<< "$BUILD_SETTINGS" | tail -n 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" /dev/stdin <<< "$2" 2>/dev/null || true
}

json_value() {
    /usr/bin/plutil -extract "$1" raw -o - - <<< "$2" 2>/dev/null || true
}

cleanup_mount() {
    if [[ -n "$MOUNT_PATH" ]]; then
        hdiutil detach "$MOUNT_PATH" -quiet >/dev/null 2>&1 || true
        rmdir "$MOUNT_PATH" >/dev/null 2>&1 || true
    fi
}

trap cleanup_mount EXIT

if (( $# != 0 )); then
    fail "Usage: make release-direct"
fi

for command in codesign ditto hdiutil lipo security shasum spctl strings xcodebuild xcrun; do
    require_command "$command"
done

if [[ ! -f "$LOCAL_CONFIG" ]]; then
    fail "Direct releases require Config/Local.xcconfig. Copy Config/Local.xcconfig.example and set DEVELOPMENT_TEAM."
fi

BUILD_SETTINGS=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings)
DEVELOPMENT_TEAM=$(build_setting DEVELOPMENT_TEAM)
PRODUCT_BUNDLE_IDENTIFIER=$(build_setting PRODUCT_BUNDLE_IDENTIFIER)
EXECUTABLE_NAME=$(build_setting EXECUTABLE_NAME)
CODE_SIGN_STYLE=$(build_setting CODE_SIGN_STYLE)
ENABLE_HARDENED_RUNTIME=$(build_setting ENABLE_HARDENED_RUNTIME)
ARCHS=$(build_setting ARCHS)
MARKETING_VERSION=$(build_setting MARKETING_VERSION)

if [[ -z "$DEVELOPMENT_TEAM" || "$DEVELOPMENT_TEAM" == "YOUR_TEAM_ID" ]]; then
    fail "Config/Local.xcconfig must define a valid DEVELOPMENT_TEAM for direct releases."
fi

if ! [[ "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    fail "Config/Local.xcconfig must define a valid Apple Developer team identifier."
fi

if [[ "$CODE_SIGN_STYLE" != "Automatic" ]]; then
    fail "Release-Direct must use automatic signing."
fi

if [[ "$ENABLE_HARDENED_RUNTIME" != "YES" ]]; then
    fail "Release-Direct must enable Hardened Runtime."
fi

if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    fail "Release-Direct must build both arm64 and x86_64."
fi

if [[ -z "$MARKETING_VERSION" ]]; then
    fail "Release-Direct must define MARKETING_VERSION."
fi

DEVELOPER_ID_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E "Developer ID Application: .*\\($DEVELOPMENT_TEAM\\)" \
    | awk 'NR == 1 { print $2 }')
if ! [[ "$DEVELOPER_ID_IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
    fail "No Developer ID Application signing identity matches DEVELOPMENT_TEAM."
fi

if ! xcrun notarytool history \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --output-format json \
    --no-progress >/dev/null 2>&1; then
    fail "Unable to authenticate with the notarytool Keychain profile '$NOTARYTOOL_PROFILE'."
fi

mkdir -p "$ARTIFACT_DIRECTORY"
rm -rf "$ARCHIVE_PATH" "$DISK_IMAGE_ROOT" "$EXPORT_PATH" "$PUBLISH_DIRECTORY"

/usr/bin/plutil -create xml1 "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c "Add :destination string export" "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c "Add :method string developer-id" "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$EXPORT_OPTIONS_PATH"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/$EXECUTABLE_NAME.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
EMBEDDED_PROFILE="$APP_PATH/Contents/embedded.provisionprofile"
EXPECTED_APPLICATION_IDENTIFIER="$DEVELOPMENT_TEAM.$PRODUCT_BUNDLE_IDENTIFIER"

[[ -d "$APP_PATH" ]] || fail "Xcode did not export $EXECUTABLE_NAME.app."
[[ -f "$APP_EXECUTABLE" ]] || fail "The exported app is missing its executable."
[[ -f "$EMBEDDED_PROFILE" ]] || fail "The exported app is missing its distribution provisioning profile."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS=$(codesign -dvv "$APP_PATH" 2>&1)
SIGNED_ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)

if ! grep -Fq "Authority=Developer ID Application:" <<< "$SIGNING_DETAILS"; then
    fail "The exported app is not signed with a Developer ID Application certificate."
fi

if ! grep -Eq 'flags=.*runtime' <<< "$SIGNING_DETAILS"; then
    fail "The exported app does not enable Hardened Runtime."
fi

SIGNED_TEAM_IDENTIFIER=$(plist_value com.apple.developer.team-identifier "$SIGNED_ENTITLEMENTS")
SIGNED_APPLICATION_IDENTIFIER=$(plist_value com.apple.application-identifier "$SIGNED_ENTITLEMENTS")
if [[ -z "$SIGNED_APPLICATION_IDENTIFIER" ]]; then
    SIGNED_APPLICATION_IDENTIFIER=$(plist_value application-identifier "$SIGNED_ENTITLEMENTS")
fi
SIGNED_KEYCHAIN_ACCESS_GROUP=$(plist_value keychain-access-groups:0 "$SIGNED_ENTITLEMENTS")
SIGNED_SANDBOX=$(plist_value com.apple.security.app-sandbox "$SIGNED_ENTITLEMENTS")
SIGNED_NETWORK_CLIENT=$(plist_value com.apple.security.network.client "$SIGNED_ENTITLEMENTS")
SIGNED_GET_TASK_ALLOW=$(plist_value get-task-allow "$SIGNED_ENTITLEMENTS")

if [[ "$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM" ]]; then
    fail "The exported app was signed by a different Apple Developer team."
fi

if [[ "$SIGNED_APPLICATION_IDENTIFIER" != "$EXPECTED_APPLICATION_IDENTIFIER" ]]; then
    fail "The exported app does not have the expected application identifier."
fi

if [[ "$SIGNED_KEYCHAIN_ACCESS_GROUP" != "$EXPECTED_APPLICATION_IDENTIFIER" ]] \
    || /usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:1' /dev/stdin \
        <<< "$SIGNED_ENTITLEMENTS" >/dev/null 2>&1; then
    fail "The exported app does not have the expected Keychain access group."
fi

if [[ "$SIGNED_SANDBOX" != "true" || "$SIGNED_NETWORK_CLIENT" != "true" ]]; then
    fail "The exported app does not preserve its required sandbox entitlements."
fi

if [[ "$SIGNED_GET_TASK_ALLOW" == "true" ]]; then
    fail "The exported app permits debugging and cannot be distributed."
fi

if ! PROFILE_CONTENT=$(security cms -D -i "$EMBEDDED_PROFILE"); then
    fail "The embedded provisioning profile could not be read."
fi

PROFILE_TEAM_IDENTIFIER=$(plist_value TeamIdentifier:0 "$PROFILE_CONTENT")
PROFILE_APPLICATION_IDENTIFIER=$(plist_value Entitlements:com.apple.application-identifier "$PROFILE_CONTENT")
if [[ -z "$PROFILE_APPLICATION_IDENTIFIER" ]]; then
    PROFILE_APPLICATION_IDENTIFIER=$(plist_value Entitlements:application-identifier "$PROFILE_CONTENT")
fi
PROFILE_KEYCHAIN_ACCESS_GROUP=$(plist_value Entitlements:keychain-access-groups:0 "$PROFILE_CONTENT")

if [[ "$PROFILE_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM" ]]; then
    fail "The embedded provisioning profile belongs to a different Apple Developer team."
fi

if [[ "$PROFILE_APPLICATION_IDENTIFIER" != "$EXPECTED_APPLICATION_IDENTIFIER" \
    && "$PROFILE_APPLICATION_IDENTIFIER" != "${DEVELOPMENT_TEAM}."* ]]; then
    fail "The embedded provisioning profile does not authorize this bundle identifier."
fi

if [[ "$PROFILE_KEYCHAIN_ACCESS_GROUP" != "$EXPECTED_APPLICATION_IDENTIFIER" \
    && "$PROFILE_KEYCHAIN_ACCESS_GROUP" != "${DEVELOPMENT_TEAM}."* ]]; then
    fail "The embedded provisioning profile does not authorize this Keychain access group."
fi

EXPORTED_ARCHITECTURES=$(lipo -archs "$APP_EXECUTABLE")
if [[ "$EXPORTED_ARCHITECTURES" != *arm64* || "$EXPORTED_ARCHITECTURES" != *x86_64* ]]; then
    fail "The exported app is not universal."
fi

if [[ -e "$APP_PATH/Contents/Resources/ComponentEditor" ]] \
    || [[ -e "$APP_PATH/Contents/Resources/DemoFixture.json" ]]; then
    fail "The exported app contains debug-only resources."
fi

if strings "$APP_EXECUTABLE" | grep -Eq 'component-editor|Component Editor|COMPONENT_EDITOR_DEV_SERVER|DemoFixture|demo fixture|MOCK_MODE'; then
    fail "The exported app contains debug-only runtime code."
fi

APP_DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
if [[ -z "$APP_DISPLAY_NAME" ]]; then
    fail "The exported app is missing CFBundleDisplayName."
fi

ARTIFACT_NAME=$(tr -cs '[:alnum:].-' '-' <<< "$APP_DISPLAY_NAME" | sed 's/^-//; s/-$//')
if [[ -z "$ARTIFACT_NAME" ]]; then
    fail "The exported app has an invalid display name for release artifacts."
fi

DMG_FILENAME="$ARTIFACT_NAME-$MARKETING_VERSION.dmg"
CHECKSUM_FILENAME="$DMG_FILENAME.sha256"
DMG_PATH="$PUBLISH_DIRECTORY/$DMG_FILENAME"
CHECKSUM_PATH="$PUBLISH_DIRECTORY/$CHECKSUM_FILENAME"
STAGED_APP_PATH="$DISK_IMAGE_ROOT/$EXECUTABLE_NAME.app"

mkdir -p "$DISK_IMAGE_ROOT" "$PUBLISH_DIRECTORY"
ditto "$APP_PATH" "$STAGED_APP_PATH"
ln -s /Applications "$DISK_IMAGE_ROOT/Applications"

if [[ ! -L "$DISK_IMAGE_ROOT/Applications" ]] \
    || [[ "$(readlink "$DISK_IMAGE_ROOT/Applications")" != "/Applications" ]]; then
    fail "The disk image staging area is missing the Applications-folder alias."
fi

hdiutil create \
    -ov \
    -format UDZO \
    -volname "$APP_DISPLAY_NAME" \
    -srcfolder "$DISK_IMAGE_ROOT" \
    "$DMG_PATH"

codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
DMG_SIGNING_DETAILS=$(codesign -dvv "$DMG_PATH" 2>&1)
if ! grep -Fq "Authority=Developer ID Application:" <<< "$DMG_SIGNING_DETAILS"; then
    fail "The disk image is not signed with a Developer ID Application certificate."
fi

set +e
NOTARY_SUBMISSION=$(xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait \
    --output-format json \
    --no-progress 2>&1)
NOTARY_SUBMISSION_EXIT=$?
set -e
NOTARY_SUBMISSION_ID=$(json_value id "$NOTARY_SUBMISSION")
NOTARY_SUBMISSION_STATUS=$(json_value status "$NOTARY_SUBMISSION")

if (( NOTARY_SUBMISSION_EXIT != 0 )) || [[ "$NOTARY_SUBMISSION_STATUS" != "Accepted" ]]; then
    if [[ -n "$NOTARY_SUBMISSION_ID" ]]; then
        xcrun notarytool log \
            "$NOTARY_SUBMISSION_ID" \
            "$NOTARY_LOG_PATH" \
            --keychain-profile "$NOTARYTOOL_PROFILE" \
            --no-progress >&2 || true
    fi
    printf '%s\n' "$NOTARY_SUBMISSION" >&2
    fail "Apple did not accept the disk image for notarization."
fi

xcrun notarytool log \
    "$NOTARY_SUBMISSION_ID" \
    "$NOTARY_LOG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --no-progress

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

MOUNT_PATH=$(mktemp -d "$ARTIFACT_DIRECTORY/mount.XXXXXX")
hdiutil attach \
    -nobrowse \
    -readonly \
    -mountpoint "$MOUNT_PATH" \
    "$DMG_PATH" >/dev/null
MOUNTED_APP_PATH="$MOUNT_PATH/$EXECUTABLE_NAME.app"
[[ -d "$MOUNTED_APP_PATH" ]] || fail "The mounted disk image is missing the app bundle."
[[ -L "$MOUNT_PATH/Applications" ]] || fail "The mounted disk image is missing the Applications-folder alias."
spctl --assess --type execute --verbose=4 "$MOUNTED_APP_PATH"

ATTACHED_MOUNT_PATH="$MOUNT_PATH"
hdiutil detach "$ATTACHED_MOUNT_PATH" -quiet
MOUNT_PATH=""
rmdir "$ATTACHED_MOUNT_PATH"

(
    cd "$PUBLISH_DIRECTORY"
    shasum -a 256 "$DMG_FILENAME" > "$CHECKSUM_FILENAME"
)

echo "Publishable artifacts:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
