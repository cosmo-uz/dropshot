APP      := Dropshot
PROJECT  := $(APP).xcodeproj
DERIVED  := build
CONFIG   ?= Debug
APP_PATH := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
XCB      := xcodebuild -project $(PROJECT) -scheme $(APP) -derivedDataPath $(DERIVED) -skipPackagePluginValidation

.PHONY: generate build release-build test run stop icon release clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) -configuration $(CONFIG) build | scripts/xcfilter.sh

release-build: generate
	$(XCB) -configuration Release build | scripts/xcfilter.sh

test:
	swift test --package-path Packages/DropshotCore

run: build stop
	open $(APP_PATH)

stop:
	-pkill -x $(APP) 2>/dev/null || true

icon:
	scripts/make-icon.sh

release:
	scripts/release.sh

clean:
	rm -rf $(DERIVED) dist $(PROJECT) Packages/DropshotCore/.build
