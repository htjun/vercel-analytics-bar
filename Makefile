PROJECT := VercelAnalyticsBar.xcodeproj
SCHEME := VercelAnalyticsBar
HOST_ARCHITECTURE := $(shell uname -m)
DERIVED_DATA_PATH := .build/DerivedData
DEBUG_APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Debug/VercelAnalyticsBar.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(HOST_ARCHITECTURE)' CODE_SIGNING_ALLOWED=NO

.PHONY: bootstrap format open run test verify

bootstrap:
	Scripts/bootstrap.sh

format:
	mint run nicklockwood/SwiftFormat@0.58.5 swiftformat .

open:
	open $(PROJECT)

run:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) build
	open $(DEBUG_APP_PATH)

test:
	swift test --package-path Packages/VercelAnalyticsCore
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) test

verify:
	Scripts/verify.sh
