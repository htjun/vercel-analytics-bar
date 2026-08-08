PROJECT := VercelAnalyticsBar.xcodeproj
SCHEME := VercelAnalyticsBar
HOST_ARCHITECTURE := $(shell uname -m)
DERIVED_DATA_PATH := .build/DerivedData
DEBUG_APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Debug/VercelAnalyticsBar.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(HOST_ARCHITECTURE)' CODE_SIGNING_ALLOWED=NO

.PHONY: bootstrap format inspector-build inspector-dev open probe run run-inspector run-inspector-bundled test verify

bootstrap:
	Scripts/bootstrap.sh

format:
	mint run nicklockwood/SwiftFormat@0.58.5 swiftformat .

inspector-build:
	npm --prefix Tools/ChartInspector run build

inspector-dev:
	npm --prefix Tools/ChartInspector run dev

open:
	open $(PROJECT)

probe:
	ruby Scripts/probe_vercel_analytics_api.rb

run:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) build
	open $(DEBUG_APP_PATH)

run-inspector:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) build
	open $(DEBUG_APP_PATH) --args --chart-inspector-dev-server

run-inspector-bundled:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) build
	open $(DEBUG_APP_PATH) --args --chart-inspector

test:
	npm --prefix Tools/ChartInspector test
	swift test --package-path Packages/VercelAnalyticsCore
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) test

verify:
	Scripts/verify.sh
