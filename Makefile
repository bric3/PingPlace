all: build

CODESIGN_IDENTITY ?= -

build:
	@mkdir -p PingPlace.app/Contents/MacOS
	@mkdir -p PingPlace.app/Contents/Resources
	@cp src/Info.plist PingPlace.app/Contents/
	@cp src/assets/app-icon/icon.icns PingPlace.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png PingPlace.app/Contents/Resources/
	swiftc src/PingPlace.swift src/NotificationPosition.swift src/NotificationGeometry.swift -o PingPlace.app/Contents/MacOS/PingPlace-x86_64 -O -target x86_64-apple-macos14.0
	swiftc src/PingPlace.swift src/NotificationPosition.swift src/NotificationGeometry.swift -o PingPlace.app/Contents/MacOS/PingPlace-arm64 -O -target arm64-apple-macos14.0
	lipo -create -output PingPlace.app/Contents/MacOS/PingPlace PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	rm PingPlace.app/Contents/MacOS/PingPlace-x86_64 PingPlace.app/Contents/MacOS/PingPlace-arm64
	codesign --entitlements src/PingPlace.entitlements -fvs "$(CODESIGN_IDENTITY)" PingPlace.app

run:
	@open PingPlace.app

test:
	@mkdir -p .build
	swiftc src/NotificationPosition.swift src/NotificationGeometry.swift tests/NotificationGeometryTests.swift -o .build/NotificationGeometryTests
	@.build/NotificationGeometryTests

clean:
	@rm -rf PingPlace.app PingPlace.app.tar.gz .build

publish:
	@tar --uid=0 --gid=0 -czf PingPlace.app.tar.gz PingPlace.app
	@shasum -a 256 PingPlace.app.tar.gz | cut -d ' ' -f 1
	@echo "don't forget to change the version number"
