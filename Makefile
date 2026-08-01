.PHONY: bootstrap format open test verify

bootstrap:
	Scripts/bootstrap.sh

format:
	mint run nicklockwood/SwiftFormat@0.58.5 swiftformat .

open:
	open VercelAnalyticsBar.xcodeproj

test:
	swift test --package-path Packages/VercelAnalyticsCore
	xcodebuild -project VercelAnalyticsBar.xcodeproj -scheme VercelAnalyticsBar -configuration Debug -destination 'platform=macOS,arch=$$(uname -m)' CODE_SIGNING_ALLOWED=NO test

verify:
	Scripts/verify.sh
