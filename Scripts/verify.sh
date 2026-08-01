#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOST_ARCHITECTURE=$(uname -m)
SWIFTFORMAT_PACKAGE=nicklockwood/SwiftFormat@0.58.5
SWIFTLINT_PACKAGE=realm/SwiftLint@0.59.1

cd "$REPOSITORY_ROOT"

if ! command -v mint >/dev/null 2>&1; then
    echo "Mint is required. Run 'make bootstrap' first." >&2
    exit 1
fi

Scripts/check-language.sh
git diff --check
mint run "$SWIFTFORMAT_PACKAGE" swiftformat --lint .
mint run "$SWIFTLINT_PACKAGE" swiftlint lint --strict --config .swiftlint.yml

swift test --package-path Packages/VercelAnalyticsCore

xcodebuild \
    -project VercelAnalyticsBar.xcodeproj \
    -scheme VercelAnalyticsBar \
    -configuration Debug \
    -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
    CODE_SIGNING_ALLOWED=NO \
    test

for configuration in Release-Direct Release-AppStore; do
    xcodebuild \
        -project VercelAnalyticsBar.xcodeproj \
        -scheme VercelAnalyticsBar \
        -configuration "$configuration" \
        -destination "platform=macOS,arch=$HOST_ARCHITECTURE" \
        CODE_SIGNING_ALLOWED=NO \
        build
done
