GO ?= go
CMD_PACKAGE ?= ./cmd/agentbox
BINARY ?= ./bin/agentbox
ARGS ?=
SETUP_ARGS ?=

.DEFAULT_GOAL := build

.PHONY: setup build test run sync-templates verify-templates fmt tidy clean

setup:
	./scripts/build-dev-image.bash $(SETUP_ARGS)

build: sync-templates
	mkdir -p "$(dir $(BINARY))"
	$(GO) build -o "$(BINARY)" $(CMD_PACKAGE)

test: verify-templates
	$(GO) test ./...

run: sync-templates
	$(GO) run $(CMD_PACKAGE) $(ARGS)

sync-templates:
	./scripts/sync-go-templates.bash

verify-templates: sync-templates
	git diff --exit-code -- internal/embeddata/templates

fmt:
	$(GO) fmt ./...

tidy:
	$(GO) mod tidy

clean:
	rm -rf ./bin
