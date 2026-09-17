# Vaktpost — pfSense monitoring and administration for iOS.
#
# One platform, but two idioms Xcode simulates as genuinely different
# devices: `make ios-run` for iPhone, `make ipados-run` for iPad. Everything
# else stays unprefixed, since there is only one of it: `make build`,
# `make archive`. The .xcodeproj is generated and never committed, so every
# target that needs one depends on `project`.
#
# vaktpost-tools/publish/vaktpost.sh calls these rather than repeating
# xcodebuild invocations, which is why `build` must stay the target that
# compiles without booting anything.

.PHONY: help project open build lint test ios-run ipados-run mac-run install archive clean oui \
	destinations devices teams set-team web web-check

# Per-machine settings: TEAM_ID, and DEVICE if you like. Written by
# `make set-team`, never committed (see .gitignore). A value on the command
# line or in the environment still wins over this file.
-include local.mk

PROJECT := Vaktpost.xcodeproj
SCHEME  := Vaktpost

help:
	@echo "  make build           does the app compile"
	@echo "  make lint            SwiftLint checks"
	@echo "  make test            the app's tests, on a simulator"
	@echo "  make ios-run         build and launch on an iPhone simulator, logs here"
	@echo "  make ipados-run      build and launch on an iPad simulator, logs here"
	@echo "  make mac-run         build and launch on this Mac as Designed for iPad"
	@echo "  make install         build signed and install on the device in DEVICE"
	@echo "  make archive         archive, signed, with a real build number"
	@echo "  make open            generate and open the project in Xcode"
	@echo ""
	@echo "  make devices         attached iPhones and iPads"
	@echo "  make teams           signing teams this Mac can use"
	@echo "  make set-team TEAM_ID=…  remember the team on this Mac (local.mk)"
	@echo "  make destinations    simulators available to run on"
	@echo ""
	@echo "  install, archive and mac-run need TEAM_ID; install also needs DEVICE."
	@echo "  Set TEAM_ID once with make set-team, or pass it each time."
	@echo "  Both are printed by the commands above:"
	@echo "    make install DEVICE=FA371128-… TEAM_ID=ABCDE12345"
	@echo ""
	@echo "  make web             serve public-web/ on :8000"
	@echo "  make web-check       validate the public website and XMLAPI lab"
	@echo "  make oui             refresh the bundled IEEE MAC vendor database"
	@echo "  make clean           remove the generated project and build products"

oui:
	@python3 Tools/generate_oui.py \
		--output Resources/OUI/ieee-oui.bin \
		--manifest Resources/OUI/README.md

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
# "1.0.0 (7)" — the form a version is written in everywhere on Apple's
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

# Refuses without a team, and says what to type rather than what is missing.
#
# The near-misses are called out by name because they are what people actually
# type: the help text says TEAM_ID, the shell says nothing, and `TEAMS=` fails
# with a message about TEAM_ID being unset that looks like the flag was ignored.
REQUIRE_TEAM = \
	if [ -z "$(TEAM_ID)" ]; then \
		echo "TEAM_ID is not set."; \
		if [ -n "$(TEAM)$(TEAMS)$(TEAMID)$(TEAM_IDS)" ]; then \
			echo "  You set TEAM, TEAMS, TEAMID or TEAM_IDS. The variable is TEAM_ID."; \
		fi; \
		echo ""; \
		echo "  make teams                       lists the team ids on this Mac"; \
		echo "  make set-team TEAM_ID=ABCDE12345 remembers one for this Mac"; \
		echo "  make $@ TEAM_ID=ABCDE12345"; \
		exit 1; \
	fi

REQUIRE_DEVICE = \
	if [ -z "$(DEVICE)" ]; then \
		echo "DEVICE is not set."; \
		echo ""; \
		echo "  make devices                     lists attached devices"; \
		echo "  make install DEVICE=<identifier> TEAM_ID=$(if $(TEAM_ID),$(TEAM_ID),ABCDE12345)"; \
		exit 1; \
	fi

# ── Compiling ────────────────────────────────────────────────────────────────

# Compiles the app, and boots nothing.
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

# Runs SwiftLint on the source tree. Fails on violation so CI can gate on it.
lint:
	@command -v swiftlint >/dev/null || { echo "SwiftLint missing — brew install swiftlint"; exit 1; }
	@swiftlint lint --strict --no-cache --config .swiftlint.yml

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
# Validates before generating anything.
#
# With `project` as a prerequisite, make runs xcodegen first and only then
# discovers TEAM_ID is missing — so a typo costs a full project regeneration
# and buries the real message under three lines of generator output.
archive:
	@$(REQUIRE_TEAM)
	@$(MAKE) --no-print-directory project
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
# `install` means the device in your hand; `ios-run`/`ipados-run` mean a
# simulator on this Mac. The verbs say what they do, because getting that
# backwards means `make install DEVICE=…` quietly builds for a simulator and
# ignores the id.

# The newest booted-or-bootable iPhone, by udid.
#
# By name is ambiguous the moment two runtimes are installed: the same device
# then exists twice and xcodebuild refuses to choose. No specific model is
# pinned here on purpose — a name written down in a Makefile goes stale as
# soon as Apple stops shipping it, and the failure is a wall of destinations
# rather than an answer.
#
# "Newest" has two parts, sorted in order: the runtime's own parsed version
# first, then the leading number in the device's own name second — neither
# is whichever happens to come last in simctl's own JSON key or list order,
# which it has never documented as version- or recency-sorted. Two runtimes
# installed in a different order than expected, or more than one iPhone
# model available under the same runtime, would otherwise pick a plausible
# but wrong device with nothing to notice it by — as happened here: iPhone
# 17 booted over iPhone 18 Pro under the same iOS 27.0 runtime, since the
# runtime-only sort correctly narrowed to that runtime but had nothing to
# say about which iPhone within it. A name with no number at all (an
# "iPhone Air"-style name, not yet a real model when this was written)
# sorts behind any numbered one rather than crashing on the missing match —
# an imperfect tie-break for a name Apple hasn't shipped, not a wrong one
# for a name it has.
SIM_ID := $(shell xcrun simctl list devices available -j 2>/dev/null | \
python3 -c 'import json,re,sys;\
ver=lambda k: tuple(map(int, re.search(r"iOS-(\d+)-(\d+)", k).groups())) if re.search(r"iOS-(\d+)-(\d+)", k) else (0,0);\
model=lambda n: int(re.search(r"(\d+)", n).group(1)) if re.search(r"(\d+)", n) else -1;\
d=json.load(sys.stdin)["devices"];\
c=[((ver(k), model(v["name"])), v) for k,vs in d.items() for v in vs if v["name"].startswith("iPhone")];\
c.sort(key=lambda pair: pair[0]);\
print(c[-1][1]["udid"] if c else "")' 2>/dev/null)

# The newest booted-or-bootable 13" iPad, by udid — Apple's own required
# class for a submission whenever the app runs on iPad, not just any
# installed iPad.
#
# "Any iPad" was the first version of this and it was wrong in practice:
# it picked whatever the newest runtime happened to list last, which one
# real run resolved to an iPad (A16) — an 11"-class device, since that
# model has never shipped in a 13" size. Screenshots taken against it
# don't satisfy Apple's requirement no matter how good they look; only
# iPad Pro and iPad Air ever ship as 13" hardware, so those are the only
# two lines this matches, and only the "13-inch" or "12.9-inch" size
# within each line — both current and older Pro/Air generations use one
# of the two in their simulator name, while the same lines' 11-inch
# siblings, and every plain iPad or iPad mini, correctly fall through and
# are never picked. Nothing installed in that class is a real "cannot
# proceed" rather than a silent wrong answer, so it fails the same way
# SIM_ID does when nothing matches: empty, caught by the same check in
# ipados-run below.
IPAD_SIM_ID := $(shell xcrun simctl list devices available -j 2>/dev/null | \
python3 -c 'import json,re,sys;\
ver=lambda k: tuple(map(int, re.search(r"iOS-(\d+)-(\d+)", k).groups())) if re.search(r"iOS-(\d+)-(\d+)", k) else (0,0);\
is13=lambda n: bool(re.match(r"iPad (Pro|Air)\b", n)) and bool(re.search(r"13-inch|12\.9-inch", n));\
d=json.load(sys.stdin)["devices"];\
c=[(ver(k), v) for k,vs in d.items() for v in vs if is13(v["name"])];\
c.sort(key=lambda pair: pair[0]);\
print(c[-1][1]["udid"] if c else "")' 2>/dev/null)

APP_INFO = \
	settings=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-sdk iphonesimulator -showBuildSettings 2>/dev/null); \
	app="$$(echo "$$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/Vaktpost.app"; \
	bundle=$$(echo "$$settings" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER /{print $$2; exit}')

# Shared by ios-run and ipados-run: everything past "which udid" is
# identical between the two idioms, so it lives here once. $(1) is the
# udid, $(2) is the label used only in the "none installed" message.
define run_on_simulator
	@test -n "$(1)" || { echo "No $(2) simulator installed. make destinations"; exit 1; }
	@set -e; $(APP_INFO); \
	test -d "$$app" || { echo "No app at $$app"; exit 1; }; \
	sim_name="$$(xcrun simctl list devices 2>/dev/null | grep "$(1)" | sed -E 's/^[[:space:]]*(.+) \([0-9A-Fa-f-]+\).*/\1/')"; \
	xcrun simctl boot $(1) 2>/dev/null || true; \
	dev_apps="$$(xcode-select -p)/Applications"; \
	{ open "$$dev_apps/Simulator.app" 2>/dev/null \
		|| open "$$dev_apps/Device Hub.app" 2>/dev/null \
		|| open -a Simulator 2>/dev/null \
		|| open -a "Device Hub" 2>/dev/null; } 2>/dev/null || true; \
	echo "If a device window didn't appear on its own, click Start on \"$${sim_name:-this device}\" in the window that just opened."; \
	xcrun simctl install $(1) "$$app"; \
	xcrun simctl launch --console-pty $(1) "$$bundle"
endef

ios-run: build
	$(call run_on_simulator,$(SIM_ID),iPhone)

ipados-run: build
	$(call run_on_simulator,$(IPAD_SIM_ID),iPad Pro or iPad Air 13-inch)

# The iPad binary, run natively on this Mac.
#
# Not a simulator and not Catalyst: the same arm64 iphoneos build that ships,
# launched under macOS. That makes it a signed build — there is no unsigned
# path to running an iOS binary outside the simulator — and the Mac has to be
# a registered device on the team, which -allowProvisioningDeviceRegistration
# takes care of on the first run.
#
# Intel Macs cannot run it at all, so this says so rather than letting
# xcodebuild print a destination list.
mac-run:
	@$(REQUIRE_TEAM)
	@test "$$(uname -m)" = arm64 || { echo "Designed for iPad needs an Apple Silicon Mac."; exit 1; }
	@$(MAKE) --no-print-directory project
	@set -e; $(bump_build); \
	dest='platform=macOS,arch=arm64,variant=Designed for iPad'; \
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$dest" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_STYLE=Automatic \
		CURRENT_PROJECT_VERSION=$$build -quiet; \
	settings=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$dest" -showBuildSettings 2>/dev/null); \
	app="$$(echo "$$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/Vaktpost.app"; \
	test -d "$$app" || { echo "No app at $$app"; exit 1; }; \
	echo "  launching Vaktpost $$version ($$build) on this Mac"; \
	open "$$app"

install:
	@$(REQUIRE_TEAM)
	@$(REQUIRE_DEVICE)
	@$(MAKE) --no-print-directory project
	@set -e; $(bump_build); \
	xcodebuild clean build -project $(PROJECT) -scheme $(SCHEME) \
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
	@command -v xcrun >/dev/null || { echo "No Xcode command line tools."; exit 1; }
	@echo "Attached devices:"
	@xcrun devicectl list devices 2>/dev/null | sed 's/^/  /' || \
		echo "  devicectl unavailable — needs Xcode 15 or later"
	@echo ""
	@echo "  Copy the Identifier column into DEVICE. Only iPhones and iPads can"
	@echo "  run this; an Apple TV in the list is not a target."

# The team id, not the certificate name.
#
# `security find-identity` prints a certificate common name whose parenthesised
# code is, for a development certificate, the certificate's own id and not the
# team's. Pasting that into TEAM_ID produces a signing failure that blames
# provisioning. The team id is the OU field of the certificate, which is what
# this reads.
teams:
	@command -v security >/dev/null || { echo "No security tool."; exit 1; }
	@printf '  %-12s %s\n' "TEAM_ID" "certificate"
	@printf '  %-12s %s\n' "----------" "-----------"
	@security find-identity -v -p codesigning 2>/dev/null \
		| sed -n 's/.*"\(.*\)"/\1/p' | sort -u | while IFS= read -r cn; do \
		ou=$$(security find-certificate -c "$$cn" -p 2>/dev/null \
			| openssl x509 -noout -subject 2>/dev/null \
			| tr ',/' '\n\n' | sed -n 's/^ *OU *= *//p' | head -1); \
		printf '  %-12s %s\n' "$${ou:-?}" "$$cn"; \
	done
	@echo ""
	@echo "  Use the left column. The code in parentheses in the certificate"
	@echo "  name is the certificate id, not the team id."

# Remember the team for this checkout, so install, archive and mac-run need no
# argument. Validated first: a team id is ten uppercase letters and digits, and
# a certificate id pasted by mistake is the usual wrong answer.
set-team:
	@if [ -z "$(TEAM_ID)" ]; then \
		echo "Usage: make set-team TEAM_ID=ABCDE12345"; \
		echo "       make teams   lists the team ids on this Mac"; \
		exit 1; \
	fi
	@printf '%s' "$(TEAM_ID)" | grep -qE '^[A-Z0-9]{10}$$' || { \
		echo "'$(TEAM_ID)' is not a team id (ten capital letters and digits)."; \
		echo "Use the left column of make teams."; exit 1; }
	@if [ -f local.mk ] && grep -q '^TEAM_ID' local.mk; then \
		sed -i.bak 's/^TEAM_ID.*/TEAM_ID ?= $(TEAM_ID)/' local.mk && rm -f local.mk.bak; \
	else \
		printf 'TEAM_ID ?= %s\n' "$(TEAM_ID)" >> local.mk; \
	fi
	@echo "Team $(TEAM_ID) saved in local.mk (not committed)."

destinations:
	@xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone|iPad' | sed 's/^ */  /'
	@echo ""
	@echo "  make test uses $(SIM_ID)"
	@echo "  make ios-run uses $(SIM_ID), make ipados-run uses $(IPAD_SIM_ID)"

# ── The website ──────────────────────────────────────────────────────────────

# public-web/ uses a small PHP entry point and has no build step.
web-check:
	@find public-web -name '*.php' -print0 | xargs -0 -n1 php -l
	@node --check public-web/lightbox.js
	@node --check public-web/lab.js
	@php ../vaktpost-tools/tests/xmlapi-lab.php

web:
	@echo "  http://localhost:8000"
	@command -v php >/dev/null || { echo "php is missing — install PHP to preview the website"; exit 1; }
	@php -S 127.0.0.1:8000 -t public-web

# ── Tidying ──────────────────────────────────────────────────────────────────

clean:
	@rm -rf $(PROJECT) build DerivedData .build
	@echo "removed the generated project and build products"
