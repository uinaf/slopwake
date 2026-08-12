SHELL := /bin/bash
.DEFAULT_GOAL := verify
HOST_ARCH := $(shell uname -m)
RELEASE_VERSION ?= $(shell sed -n '1p' VERSION)
BUILD_NUMBER ?= 1

.PHONY: project test core-test app-test release-check build verify release clean

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

release-check:
	./scripts/check-release-contract.sh

build: project
	xcodebuild \
		-project Slopwake.xcodeproj \
		-scheme Slopwake \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		MARKETING_VERSION=$(RELEASE_VERSION) \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		build

release: build
	RELEASE_VERSION=$(RELEASE_VERSION) ./scripts/release.sh

verify: test release-check build

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
