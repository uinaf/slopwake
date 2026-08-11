SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project test build smoke verify clean

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

smoke: build
	./scripts/smoke-app.sh

verify: test smoke

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
