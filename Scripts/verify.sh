#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOST_ARCHITECTURE=$(uname -m)
DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/VerifyDerivedData"
INSPECTOR_ROOT="$REPOSITORY_ROOT/Tools/ChartInspector"
SWIFTFORMAT_PACKAGE=nicklockwood/SwiftFormat@0.58.5
SWIFTLINT_PACKAGE=realm/SwiftLint@0.59.1

cd "$REPOSITORY_ROOT"

if ! command -v mint >/dev/null 2>&1; then
    echo "Mint is required. Run 'make bootstrap' first." >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "Node.js and npm are required. Run 'make bootstrap' first." >&2
    exit 1
fi

Scripts/check-language.sh
git diff --check
mint run "$SWIFTFORMAT_PACKAGE" swiftformat --lint .
mint run "$SWIFTLINT_PACKAGE" swiftlint lint --strict --config .swiftlint.yml

ENTITLEMENTS_PATH="$REPOSITORY_ROOT/VercelAnalyticsBar/SupportingFiles/VercelAnalyticsBar.entitlements"
KEYCHAIN_ACCESS_GROUP=$(
    /usr/bin/plutil -extract keychain-access-groups.0 raw -o - "$ENTITLEMENTS_PATH" 2>/dev/null || true
)
EXPECTED_KEYCHAIN_ACCESS_GROUP='$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'
if [[ "$KEYCHAIN_ACCESS_GROUP" != "$EXPECTED_KEYCHAIN_ACCESS_GROUP" ]] \
    || /usr/bin/plutil -extract keychain-access-groups.1 raw -o - "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
    echo "The app must declare only its canonical Keychain access group." >&2
    exit 1
fi

npm --prefix "$INSPECTOR_ROOT" test
INSPECTOR_BUNDLE="$REPOSITORY_ROOT/VercelAnalyticsBar/Resources/ChartInspector"
INSPECTOR_HASH_BEFORE=$(find "$INSPECTOR_BUNDLE" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)
npm --prefix "$INSPECTOR_ROOT" run build
INSPECTOR_HASH_AFTER=$(find "$INSPECTOR_BUNDLE" -type f -exec shasum -a 256 {} + | LC_ALL=C sort)
if [[ "$INSPECTOR_HASH_BEFORE" != "$INSPECTOR_HASH_AFTER" ]]; then
    echo "The bundled Chart Inspector is stale. Run 'make inspector-build'." >&2
    exit 1
fi

if ! grep -Fq "default-src 'none'" "$INSPECTOR_BUNDLE/index.html"; then
    echo "The bundled Chart Inspector is missing its Content Security Policy." >&2
    exit 1
fi
if ! find "$INSPECTOR_BUNDLE/assets" -type f -exec /usr/bin/ruby -e '
    allowed = [
        "http://www.w3.org/1998/Math/MathML",
        "http://www.w3.org/1999/xlink",
        "http://www.w3.org/2000/svg",
        "http://www.w3.org/XML/1998/namespace",
    ]
    ARGV.each do |path|
        content = File.binread(path)
        allowed.each { |identifier| content = content.gsub(identifier, "") }
        abort("Remote URL in #{path}") if content.match?(%r{https?://})
    end
' {} +; then
    echo "The bundled Chart Inspector contains a remote URL." >&2
    exit 1
fi

swift test --package-path Packages/VercelAnalyticsCore

xcodebuild \
    -project VercelAnalyticsBar.xcodeproj \
    -scheme VercelAnalyticsBar \
    -configuration Debug \
    -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    test

DEBUG_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/VercelAnalyticsBar.app"
if [[ ! -f "$DEBUG_APP_PATH/Contents/Resources/ChartInspector/index.html" ]]; then
    echo "The Debug app is missing bundled Chart Inspector resources." >&2
    exit 1
fi

for configuration in Release-Direct Release-AppStore; do
    if ! xcodebuild \
        -project VercelAnalyticsBar.xcodeproj \
        -scheme VercelAnalyticsBar \
        -configuration "$configuration" \
        -showBuildSettings \
        | grep -Eq '^[[:space:]]*ENABLE_HARDENED_RUNTIME = YES$'; then
        echo "$configuration does not enable Hardened Runtime." >&2
        exit 1
    fi

    xcodebuild \
        -project VercelAnalyticsBar.xcodeproj \
        -scheme VercelAnalyticsBar \
        -configuration "$configuration" \
        -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        build

    RELEASE_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$configuration/VercelAnalyticsBar.app"
    if [[ -e "$RELEASE_APP_PATH/Contents/Resources/ChartInspector" ]]; then
        echo "$configuration unexpectedly contains Chart Inspector resources." >&2
        exit 1
    fi
    if [[ -e "$RELEASE_APP_PATH/Contents/Resources/DemoFixture.json" ]]; then
        echo "$configuration unexpectedly contains a demo fixture." >&2
        exit 1
    fi
    if strings "$RELEASE_APP_PATH/Contents/MacOS/VercelAnalyticsBar" \
        | grep -Eq "chart-inspector|Chart Inspector|CHART_INSPECTOR_DEV_SERVER"; then
        echo "$configuration unexpectedly contains Chart Inspector runtime strings." >&2
        exit 1
    fi
    if strings "$RELEASE_APP_PATH/Contents/MacOS/VercelAnalyticsBar" \
        | grep -Eq "DemoFixture|demo fixture|MOCK_MODE"; then
        echo "$configuration unexpectedly contains demo runtime strings." >&2
        exit 1
    fi
done
