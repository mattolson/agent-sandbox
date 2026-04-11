GO ?= go
CMD_PACKAGE ?= ./cmd/agentbox
DIST_DIR ?= ./dist
BIN_DIR ?= ./bin
BINARY ?= $(BIN_DIR)/agentbox
ARGS ?=
SETUP_ARGS ?=
CGO_ENABLED ?= 0
TARGETS ?= darwin/amd64 darwin/arm64 linux/amd64 linux/arm64
HOST_UNAME_S := $(shell uname -s)
HOST_UNAME_M := $(shell uname -m)
HOST_GOOS := $(if $(filter Darwin,$(HOST_UNAME_S)),darwin,$(if $(filter Linux,$(HOST_UNAME_S)),linux,unknown))
HOST_GOARCH := $(if $(filter arm64 aarch64,$(HOST_UNAME_M)),arm64,$(if $(filter x86_64 amd64,$(HOST_UNAME_M)),amd64,unknown))
HOST_BINARY := $(DIST_DIR)/agentbox-$(HOST_GOOS)-$(HOST_GOARCH)
HOST_BINARY_LINK := ../$(patsubst ./%,%,$(HOST_BINARY))

.DEFAULT_GOAL := build

.PHONY: setup build test run fmt tidy clean

setup:
	./scripts/build-dev-image.bash $(SETUP_ARGS)

build:
	mkdir -p "$(DIST_DIR)" "$(BIN_DIR)"
	set -eu; \
	for target in $(TARGETS); do \
		goos=$${target%/*}; \
		goarch=$${target#*/}; \
		output="$(DIST_DIR)/agentbox-$${goos}-$${goarch}"; \
		CGO_ENABLED=$(CGO_ENABLED) GOOS=$$goos GOARCH=$$goarch $(GO) build -o "$$output" $(CMD_PACKAGE); \
	done
	if [ "$(HOST_GOOS)" = "unknown" ] || [ "$(HOST_GOARCH)" = "unknown" ]; then \
		printf 'Unsupported host platform for bin symlink: %s/%s\n' "$(HOST_UNAME_S)" "$(HOST_UNAME_M)" >&2; \
		exit 1; \
	fi
	ln -sfn "$(HOST_BINARY_LINK)" "$(BINARY)"

test:
	$(GO) test ./...

run:
	$(GO) run $(CMD_PACKAGE) $(ARGS)

fmt:
	$(GO) fmt ./...

tidy:
	$(GO) mod tidy

clean:
	rm -rf "$(BIN_DIR)" "$(DIST_DIR)"
