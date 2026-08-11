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

npm --prefix "$INSPECTOR_ROOT" test
npm --prefix "$INSPECTOR_ROOT" run build
git diff --exit-code HEAD -- VercelAnalyticsBar/Resources/ChartInspector

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
