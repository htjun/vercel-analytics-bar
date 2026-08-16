PROJECT := VercelAnalyticsBar.xcodeproj
SCHEME := VercelAnalyticsBar
HOST_ARCHITECTURE := $(shell uname -m)
DERIVED_DATA_PATH := .build/DerivedData
DEBUG_APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Debug/VercelAnalyticsBar.app
UNSIGNED_XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(HOST_ARCHITECTURE)' CODE_SIGNING_ALLOWED=NO

.PHONY: bootstrap format editor-build open probe release-direct run run-editor run-mock test verify

FIXTURE ?= ideal

bootstrap:
	Scripts/bootstrap.sh

format:
	mint run nicklockwood/SwiftFormat@0.58.5 swiftformat .

editor-build:
	npm --prefix Tools/ComponentEditor run build

open:
	open $(PROJECT)

probe:
	ruby Scripts/probe_vercel_analytics_api.rb

release-direct:
	Scripts/release_direct.sh

run:
	Scripts/run_debug.sh

run-editor:
	Scripts/run_editor.sh "$(FIXTURE)"

run-mock:
	Scripts/run_mock.sh "$(FIXTURE)"

test:
	npm --prefix Tools/ComponentEditor test
	swift test --package-path Packages/VercelAnalyticsCore
	$(UNSIGNED_XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DATA_PATH) test

verify:
	Scripts/verify.sh
