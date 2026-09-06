# Vaktpost — a read-only pfSense dashboard for iOS.
#
# One platform, so the verbs are unprefixed: `make build`, `make run`,
# `make archive`. The .xcodeproj is generated and never committed, so every
# target that needs one depends on `project`.
#
# vaktpost-tools/publish/vaktpost.sh calls these rather than repeating
# xcodebuild invocations, which is why `build` must stay the target that
# compiles without booting anything.

.PHONY: help project open build test run install archive clean \
	destinations devices teams web

PROJECT := Vaktpost.xcodeproj
SCHEME  := Vaktpost

help:
	@echo "  make build           does the app compile"
	@echo "  make test            the app's tests, on a simulator"
	@echo "  make run             build and launch on a simulator, logs here"
	@echo "  make install         build signed and install on the device in DEVICE"
	@echo "  make archive         archive, signed, with a real build number"
	@echo "  make open            generate and open the project in Xcode"
	@echo ""
	@echo "  make devices         attached iPhones and iPads"
	@echo "  make teams           signing teams this Mac can use"
	@echo "  make destinations    simulators available to run on"
	@echo ""
	@echo "  install and archive need TEAM_ID, install also needs DEVICE:"
	@echo "    make install DEVICE=00008132-… TEAM_ID=ABCDE12345"
	@echo ""
	@echo "  make web             serve public-web/ on :8000"
	@echo "  make clean           remove the generated project and build products"

# ── Generating the project ───────────────────────────────────────────────────

project:
	@command -v xcodegen >/dev/null || { echo "xcodegen is missing — brew install xcodegen"; exit 1; }
	@xcodegen generate

# Generates first, because the project is not committed. `open` on a path that
# does not exist yet fails with a message about a missing file rather than
# about the missing step, which is a confusing way to learn how this repository
# works.
open: project
	@open $(PROJECT)

# ── Build numbers ────────────────────────────────────────────────────────────
#
# build.number holds the last number used. This bumps it and leaves the new
# value in $$build, and reads the version beside it so a summary can say
# "0.1.0 (7)" — the form a version is written in everywhere on Apple's
# platforms.
#
# A shell fragment rather than a $(shell …) expansion, so a recipe can both
# pass the number to xcodebuild and print it. Doing that with an expansion
# calls the fragment twice, which bumps twice and prints the wrong one.
#
# Not derived from git: a commit count changes when somebody rebases and stays
# still while you build twenty times chasing one bug, which is backwards.
define bump_build
build=$$(( $$(cat build.number 2>/dev/null || echo 0) + 1 )); \
echo $$build > build.number; \
version=$$(awk -F' = ' '/^MARKETING_VERSION/{print $$2; exit}' Config/iOS.xcconfig)
endef

REQUIRE_TEAM = \
	if [ -z "$(TEAM_ID)" ]; then \
		echo "TEAM_ID is not set. make teams"; exit 1; \
	fi

# ── Compiling ────────────────────────────────────────────────────────────────

# Compiles the app and the widget extension, and boots nothing.
#
# `generic/platform=iOS Simulator` needs no installed simulator and starts no
# device, so this catches every compile error without a simulator appearing on
# screen. It is what the publish check runs: publishing has to be quick and
# must never launch an app.
build: project
	@set -e; $(bump_build); \
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
		CURRENT_PROJECT_VERSION=$$build -quiet; \
	echo "  built Vaktpost $$version ($$build)"

# The slow one. `xcodebuild test` installs the test host on a simulator and
# runs it, which means booting a device and waiting. Worth doing deliberately;
# not worth doing before every push.
test: project
	@test -n "$(SIM_ID)" || { echo "No iPhone simulator installed. make destinations"; exit 1; }
	@xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination 'id=$(SIM_ID)'

# Xcode's own Product > Archive reads whatever is baked into iOS.xcconfig,
# which is deliberately the sentinel 1. Archiving through make instead bumps
# the counter the same way every other target does and passes the result to
# `xcodebuild archive`, so the .xcarchive already has a real number before the
# Organizer opens. Without this, every archive carries build 1 and App Store
# Connect refuses the second upload.
archive: project
	@$(REQUIRE_TEAM)
	@echo "Signing with team $(TEAM_ID)"
	@mkdir -p build
	@set -e; $(bump_build); \
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) \
		-archivePath build/Vaktpost.xcarchive \
		-destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_STYLE=Automatic \
		CURRENT_PROJECT_VERSION=$$build; \
	echo ""; \
	echo "  archived Vaktpost $$version ($$build)"
	@open build/Vaktpost.xcarchive

# ── Running ──────────────────────────────────────────────────────────────────
#
# `install` means the device in your hand; `run` means a simulator on this Mac.
# The verbs say what they do, because getting that backwards means
# `make install DEVICE=…` quietly builds for a simulator and ignores the id.

# The newest booted-or-bootable iPhone, by udid.
#
# By name is ambiguous the moment two runtimes are installed: the same device
# then exists twice and xcodebuild refuses to choose. No model is written down
# here on purpose — a name pinned in a Makefile goes stale as soon as Apple
# stops shipping it, and the failure is a wall of destinations rather than an
# answer.
SIM_ID := $(shell xcrun simctl list devices available -j 2>/dev/null | \
	python3 -c 'import json,sys;\
d=json.load(sys.stdin)["devices"];\
c=[v for k,vs in d.items() for v in vs if v["name"].startswith("iPhone")];\
print(c[-1]["udid"] if c else "")' 2>/dev/null)

APP_INFO = \
	settings=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-sdk iphonesimulator -showBuildSettings 2>/dev/null); \
	app="$$(echo "$$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/Vaktpost.app"; \
	bundle=$$(echo "$$settings" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER /{print $$2; exit}')

run: build
	@test -n "$(SIM_ID)" || { echo "No iPhone simulator installed. make destinations"; exit 1; }
	@set -e; $(APP_INFO); \
	test -d "$$app" || { echo "No app at $$app"; exit 1; }; \
	xcrun simctl boot $(SIM_ID) 2>/dev/null || true; \
	open -a Simulator; \
	xcrun simctl install $(SIM_ID) "$$app"; \
	xcrun simctl launch --console-pty $(SIM_ID) "$$bundle"

install: project
	@$(REQUIRE_TEAM)
	@test -n "$(DEVICE)" || { echo "DEVICE is not set. make devices"; exit 1; }
	@set -e; $(bump_build); \
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'id=$(DEVICE)' -allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_STYLE=Automatic \
		CURRENT_PROJECT_VERSION=$$build -quiet; \
	settings=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'id=$(DEVICE)' -showBuildSettings 2>/dev/null); \
	app="$$(echo "$$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/Vaktpost.app"; \
	test -d "$$app" || { echo "No app at $$app"; exit 1; }; \
	xcrun devicectl device install app --device $(DEVICE) "$$app"; \
	echo ""; \
	echo "  installed Vaktpost $$version ($$build)"

# ── What this Mac can do ─────────────────────────────────────────────────────

devices:
	@echo "Attached devices:"
	@xcrun devicectl list devices 2>/dev/null | sed 's/^/  /' || \
		echo "  devicectl unavailable — needs Xcode 15 or later"

teams:
	@echo "Signing teams:"
	@security find-identity -v -p codesigning 2>/dev/null | \
		sed -n 's/.*"\(.*\)".*/  \1/p' | sort -u || echo "  none found"

destinations:
	@xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone|iPad' | sed 's/^ */  /'
	@echo ""
	@echo "  make test and make run use $(SIM_ID)"

# ── The website ──────────────────────────────────────────────────────────────

# public-web/ is static with no build step, so serving it is the whole story.
web:
	@echo "  http://localhost:8000"
	@python3 -m http.server 8000 --directory public-web

# ── Tidying ──────────────────────────────────────────────────────────────────

clean:
	@rm -rf $(PROJECT) build DerivedData .build
	@echo "removed the generated project and build products"
