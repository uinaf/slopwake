SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project test build verify clean

project:
	./scripts/generate-project.sh

test:
	swift test --parallel

build: project
	xcodebuild \
		-project Slopwake.xcodeproj \
		-scheme Slopwake \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		build

verify: test build

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
