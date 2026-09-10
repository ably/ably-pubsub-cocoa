SHELL := /bin/bash
.PHONY: help setup submodules

default: help

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'

# COLORS
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

## ----- Helper functions ------

# Helper target for declaring an external executable as a recipe dependency.
# For example,
#   `my_target: | _program_awk`
# will fail before running the target named `my_target` if the command `awk` is
# not found on the system path.
_program_%: FORCE
	@_=$(or $(shell which $* 2> /dev/null),$(error `$*` command not found. Please install `$*` and try again))

# Helper target for declaring required environment variables.
#
# For example,
#   `my_target`: | _var_PARAMETER`
#
# will fail before running `my_target` if the variable `PARAMETER` is not declared.
_var_%: FORCE
	@_=$(or $($*),$(error `$*` is a required parameter))

## ------ Commmands -----------

TARGET_MAX_CHAR_NUM=20
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' \
	$(MAKEFILE_LIST)

## Update dependencies (Git submodules)
update: submodules

## -- Linting --

## [Lint] Check EditorConfig compliance and LiveObjects test seams
lint:
	editorconfig-checker
	bash Scripts/check-liveobjects-test-seams.sh

## -- Source Code Tasks --

## Update Git submodules
submodules:
	$(info Updating submodules…)

	git submodule update --init --recursive
	
## -- Testing --

## [Tests] Run tests on iOS 26.2 using sandbox environment
test_iOS:
	ABLY_ENV="sandbox" NAME="ably-iOS" bundle exec fastlane test_iOS26_2

## [Tests] Run tests on tvOS 26.2 using sandbox environment
test_tvOS:
	ABLY_ENV="sandbox" NAME="ably-tvOS" bundle exec fastlane test_tvOS26_2

## [Tests] Run tests on macOS using sandbox environment
test_macOS:
	ABLY_ENV="sandbox" NAME="ably-macOS" bundle exec fastlane test_macOS

## -- Version --

## [Version] Bump Patch Version, creating Git commit and tag
bump_patch:
	$(info Bumping version Patch type…)

	Scripts/set-version.sh `Scripts/get-version.sh | awk -F. '{$$NF = $$NF + 1;} 1' | sed 's/ /./g'`

## [Version] Bump Minor Version, creating Git commit and tag
bump_minor:
	$(info Bumping version Minor type…)

	Scripts/set-version.sh `Scripts/get-version.sh | awk -F. '{$$(NF-1) = $$(NF-1) + 1;} 1' | sed 's/ /./g' | awk -F. '{$$(NF) = 0;} 1' | sed 's/ /./g' `

## [Version] Bump Major Version, creating Git commit and tag
bump_major:
	$(info Bumping version Major type…)

	Scripts/set-version.sh `Scripts/get-version.sh | awk -F. '{$$(NF-2) = $$(NF-2) + 1;} 1' | sed 's/ /./g' | awk -F. '{$$(NF-1) = 0;} 1' | sed 's/ /./g' | awk -F. '{$$(NF) = 0;} 1' | sed 's/ /./g' `
