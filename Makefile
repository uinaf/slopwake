SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project test app-test build smoke notarized-smoke verify clean

project:
	./scripts/generate-project.sh

test:
	swift test --parallel

app-test: project
	xcodebuild \
		-project Slopwake.xcodeproj \
		-scheme Slopwake \
		-configuration Debug \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath DerivedData \
		CODE_SIGN_IDENTITY=- \
		ONLY_ACTIVE_ARCH=YES \
		ARCHS=arm64 \
		test

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

notarized-smoke:
	./scripts/notarize-smoke.sh

verify: test app-test smoke

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
