.PHONY: build run clean

build:
	swift build -c release

run:
	swift run

debug:
	swift build
	./.build/debug/Tenfe

xcode:
	swift package generate-xcodeproj
	open Tenfe.xcodeproj

app: build
	mkdir -p Tenfe.app/Contents/MacOS
	mkdir -p Tenfe.app/Contents/Resources
	cp .build/release/Tenfe Tenfe.app/Contents/MacOS/
	cp Info.plist Tenfe.app/Contents/
	echo "Built Tenfe.app successfully!"

clean:
	swift package clean
	rm -rf .build
	rm -rf Tenfe.xcodeproj
	rm -rf Tenfe.app

test:
	swift test