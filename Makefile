.PHONY: all build debug-build generate-build-info run test clean publish save-codesign-identity clear-codesign-identity

all: build

CODESIGN_IDENTITY_FILE ?= .codesign_identity
BUILD_INFO_SWIFT ?= .build/BuildInfo.generated.swift
APP_SWIFT_SOURCES = $(sort $(wildcard src/*.swift)) $(BUILD_INFO_SWIFT)
TEST_SWIFT_SOURCES = src/NotificationPosition.swift src/NotificationGeometry.swift src/NotificationPolicyTypes.swift src/NotificationMovePolicy.swift src/NotificationCenterStatePolicy.swift src/ScreenResolutionPolicy.swift src/TreeTraversal.swift src/NotificationController.swift src/NotificationWindowPlacementEngine.swift tests/NotificationBehaviorTests.swift

ifneq ("$(wildcard $(CODESIGN_IDENTITY_FILE))","")
CODESIGN_IDENTITY ?= $(shell cat $(CODESIGN_IDENTITY_FILE))
else
CODESIGN_IDENTITY ?= -
endif

define warn_adhoc_signing
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "warning: using ad-hoc signing (-)."; \
		echo "warning: macOS Accessibility permissions may need re-approval for each build."; \
		echo "warning: run 'make save-codesign-identity CODESIGN_IDENTITY=\"Apple Development: Your Name (TEAMID)\"' to stabilize signing."; \
	fi
endef

build:
	@mkdir -p .build
	@$(MAKE) generate-build-info
	@mkdir -p PingPlace.app/Contents/MacOS
	@mkdir -p PingPlace.app/Contents/Resources
	@cp src/Info.plist PingPlace.app/Contents/
	@cp src/assets/app-icon/icon.icns PingPlace.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png PingPlace.app/Contents/Resources/
	swiftc $(APP_SWIFT_SOURCES) -o PingPlace.app/Contents/MacOS/PingPlace-x86_64 -O -target x86_64-apple-macos14.0
	swiftc $(APP_SWIFT_SOURCES) -o PingPlace.app/Contents/MacOS/PingPlace-arm64 -O -target arm64-apple-macos14.0
	lipo -create -output PingPlace.app/Contents/MacOS/PingPlace PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	rm PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	$(warn_adhoc_signing)
	codesign --entitlements src/PingPlace.entitlements -fvs "$(CODESIGN_IDENTITY)" PingPlace.app

debug-build:
	@mkdir -p .build
	@$(MAKE) generate-build-info
	@mkdir -p PingPlace.app/Contents/MacOS
	@mkdir -p PingPlace.app/Contents/Resources
	@cp src/Info.plist PingPlace.app/Contents/
	@cp src/assets/app-icon/icon.icns PingPlace.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png PingPlace.app/Contents/Resources/
	swiftc $(APP_SWIFT_SOURCES) -o PingPlace.app/Contents/MacOS/PingPlace-x86_64 -Onone -g -D PINGPLACE_DEBUG_BUILD -target x86_64-apple-macos14.0
	swiftc $(APP_SWIFT_SOURCES) -o PingPlace.app/Contents/MacOS/PingPlace-arm64 -Onone -g -D PINGPLACE_DEBUG_BUILD -target arm64-apple-macos14.0
	lipo -create -output PingPlace.app/Contents/MacOS/PingPlace PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	rm PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	$(warn_adhoc_signing)
	codesign --entitlements src/PingPlace.entitlements -fvs "$(CODESIGN_IDENTITY)" PingPlace.app

generate-build-info:
	@mkdir -p .build
	@BUILD_COMMIT=$$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown); \
	BUILD_DIRTY=$$(if git diff --quiet --ignore-submodules HEAD -- 2>/dev/null && git diff --cached --quiet --ignore-submodules -- 2>/dev/null && [ -z "$$(git ls-files --others --exclude-standard -- src tests Makefile 2>/dev/null)" ]; then echo clean; else echo dirty; fi); \
	BUILD_TIMESTAMP=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	SOURCE_FINGERPRINT=$$((find src -type f -print 2>/dev/null; find tests -type f -print 2>/dev/null; printf '%s\n' Makefile) | LC_ALL=C sort | while IFS= read -r file; do shasum "$$file"; done | shasum | awk '{print $$1}'); \
	printf '%s\n' \
		'struct GeneratedBuildInfo {' \
		"    static let gitCommit = \"$$BUILD_COMMIT\"" \
		"    static let gitDirtyState = \"$$BUILD_DIRTY\"" \
		"    static let buildTimestamp = \"$$BUILD_TIMESTAMP\"" \
		"    static let sourceFingerprint = \"$$SOURCE_FINGERPRINT\"" \
		'}' > "$(BUILD_INFO_SWIFT)"

run:
	@open PingPlace.app

test:
	@mkdir -p .build
	@if [ -f tests/NotificationBehaviorTests.swift ]; then \
		swiftc $(TEST_SWIFT_SOURCES) -o .build/NotificationBehaviorTests; \
		.build/NotificationBehaviorTests; \
	else \
		echo "No NotificationBehaviorTests on this branch."; \
	fi

clean:
	@rm -rf PingPlace.app PingPlace.app.tar.gz .build

publish:
	@tar --uid=0 --gid=0 -czf PingPlace.app.tar.gz PingPlace.app
	@shasum -a 256 PingPlace.app.tar.gz | cut -d ' ' -f 1
	@echo "don't forget to change the version number"

save-codesign-identity:
	@test -n "$(CODESIGN_IDENTITY)" || (echo "error: set CODESIGN_IDENTITY to your Apple signing identity"; exit 1)
	@test "$(CODESIGN_IDENTITY)" != "-" || (echo "error: refusing to save ad-hoc identity '-'"; exit 1)
	@printf "%s" "$(CODESIGN_IDENTITY)" > "$(CODESIGN_IDENTITY_FILE)"
	@echo "Saved codesign identity to $(CODESIGN_IDENTITY_FILE)"

clear-codesign-identity:
	@rm -f "$(CODESIGN_IDENTITY_FILE)"
	@echo "Cleared $(CODESIGN_IDENTITY_FILE); builds will use ad-hoc signing unless CODESIGN_IDENTITY is set."
