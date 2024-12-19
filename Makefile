
.PHONY: default
default: check

.PHONY: check
check: shellcheck github-action-syntax

.PHONY: shellcheck
shellcheck:
	shellcheck scripts/*.sh

.PHONY: github-action-syntax
github-action-syntax:
	action-validator action.yml .github/**/*.yml
