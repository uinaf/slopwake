SHELL := /bin/bash
.DEFAULT_GOAL := verify
HOST_ARCH := $(shell uname -m)

.PHONY: project test core-test app-test build verify release clean

project:
	./scripts/generate-project.sh

test: core-test app-test

core-test:
	swift test --parallel

app-test: project
	xcodebuild \
		-project Slopwake.xcodeproj \
		-scheme Slopwake \
		-configuration Debug \
		-destination 'platform=macOS,arch=$(HOST_ARCH)' \
		-derivedDataPath DerivedData \
		CODE_SIGN_IDENTITY=- \
		ONLY_ACTIVE_ARCH=YES \
		ARCHS=$(HOST_ARCH) \
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

release:
	./scripts/release.sh

verify: test build

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
