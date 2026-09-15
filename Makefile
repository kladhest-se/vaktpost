# Vaktpost — pfSense monitoring and administration for iOS.
#
# One platform, so the verbs are unprefixed: `make build`, `make run`,
# `make archive`. The .xcodeproj is generated and never committed, so every
# target that needs one depends on `project`.
#
# vaktpost-tools/publish/vaktpost.sh calls these rather than repeating
# xcodebuild invocations, which is why `build` must stay the target that
# compiles without booting anything.

.PHONY: help project open build lint test run install archive clean oui \
	destinations devices teams web web-check

PROJECT := Vaktpost.xcodeproj
SCHEME  := Vaktpost

help:
	@echo "  make build           does the app compile"
	@echo "  make lint            SwiftLint checks"
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
	@echo "  install and archive need TEAM_ID; install also needs DEVICE."
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

destinations:
	@xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone|iPad' | sed 's/^ */  /'
	@echo ""
	@echo "  make test and make run use $(SIM_ID)"

# ── The website ──────────────────────────────────────────────────────────────

# public-web/ uses a small PHP entry point and has no build step.
web-check:
	@find public-web -name '*.php' -print0 | xargs -0 -n1 php -l
	@node --check public-web/theme.js
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
