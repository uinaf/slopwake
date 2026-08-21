SHELL := /bin/bash
.DEFAULT_GOAL := verify
HOST_ARCH := $(shell uname -m)
RELEASE_VERSION ?= $(shell sed -n '1p' VERSION)
BUILD_NUMBER ?= 1
VERIFY_JOBS ?= 4
TEST_DERIVED_DATA ?= DerivedData/Test
BUILD_DERIVED_DATA ?= DerivedData/Build

.PHONY: project test core-test app-test release-check build verify verify-lanes verify-product-lanes release clean

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
		-derivedDataPath $(TEST_DERIVED_DATA) \
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
		-derivedDataPath $(BUILD_DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		MARKETING_VERSION=$(RELEASE_VERSION) \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		build

release: build
	RELEASE_VERSION=$(RELEASE_VERSION) ./scripts/release.sh

verify:
	+$(MAKE) --no-print-directory -j$(VERIFY_JOBS) verify-lanes

verify-lanes: verify-product-lanes release-check

verify-product-lanes: core-test app-test build

clean:
	swift package clean
	rm -rf DerivedData Slopwake.xcodeproj
