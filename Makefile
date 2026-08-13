PROJECT := VercelAnalyticsBar.xcodeproj
SCHEME := VercelAnalyticsBar
HOST_ARCHITECTURE := $(shell uname -m)
DERIVED_DATA_PATH := .build/DerivedData
DEBUG_APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Debug/VercelAnalyticsBar.app
UNSIGNED_XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(HOST_ARCHITECTURE)' CODE_SIGNING_ALLOWED=NO

.PHONY: bootstrap format inspector-build inspector-dev open probe run run-inspector run-inspector-bundled run-mock test verify

FIXTURE ?= ideal

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
	Scripts/run_debug.sh

run-inspector:
	Scripts/run_inspector_dev.sh

run-inspector-bundled:
	Scripts/run_debug.sh --chart-inspector

run-mock:
	Scripts/run_mock.sh "$(FIXTURE)"

test:
	npm --prefix Tools/ChartInspector test
	swift test --package-path Packages/VercelAnalyticsCore
	$(UNSIGNED_XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) test

verify:
	Scripts/verify.sh
