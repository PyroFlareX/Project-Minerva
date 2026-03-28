# =============================================================================
# Torchform DE — Makefile
#
# Targets you'll use most:
#   make run-shell          Open the shell UI in two desktop windows (quick test)
#   make run-shell-radial   Open with the system radial menu shown
#   make run-shell-idle     Open with the lower screen in idle/status mode
#   make run-compositor     Run the Wayland compositor (Winit nested window)
#   make check              Cargo check all crates (fast — no codegen)
#   make build              Cargo build (debug) all crates
#   make dev                Enter the Docker dev container interactively
#   make dev-build          Build the Docker image
#   make send-input         Run the mock input sender (gamepad events via socket)
# =============================================================================

DOCKER_IMAGE  := torchform-dev
DOCKER_RUN    := docker run --rm -it \
                   --network=host \
                   -e DISPLAY=$(DISPLAY) \
                   -e WAYLAND_DISPLAY=$(WAYLAND_DISPLAY) \
                   -e XDG_RUNTIME_DIR=/tmp/runtime-dev \
                   -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
                   $(shell [ -n "$(WAYLAND_DISPLAY)" ] && echo "-v $(XDG_RUNTIME_DIR)/$(WAYLAND_DISPLAY):/tmp/runtime-dev/$(WAYLAND_DISPLAY):rw") \
                   -v $(shell pwd):/workspace:cached \
                   -v torchform-cargo-registry:/usr/local/cargo/registry \
                   -v torchform-cargo-git:/usr/local/cargo/git \
                   -w /workspace \
                   $(DOCKER_IMAGE)

# Detect whether cargo is available natively or we need Docker
CARGO := $(shell command -v cargo 2>/dev/null || echo "$(DOCKER_RUN) cargo")

.PHONY: all check build run-emulator run-shell run-shell-radial run-shell-switcher \
        run-shell-idle run-compositor dev dev-build send-input clean help

all: build

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "  Torchform DE — development targets"
	@echo ""
	@echo "  Testing (no device needed):"
	@echo "    make run-emulator        Emulator: both screens in one hardware-frame window"
	@echo "    make run-shell-radial    Emulator — starts with system radial open"
	@echo "    make run-shell-switcher  Emulator — starts with app switcher open"
	@echo "    make run-shell-idle      Emulator — lower screen in idle/status mode"
	@echo "    make run-standalone      Two separate windows (mirrors physical layout)"
	@echo "    make run-compositor      Wayland compositor (Winit, nested window)"
	@echo "    make send-input          Mock gamepad event sender"
	@echo ""
	@echo "  Build (shell only — no hardware libs required):"
	@echo "    make check               cargo check torchform-shell"
	@echo "    make build               cargo build torchform-shell (debug)"
	@echo "    make build-release       cargo build torchform-shell (release)"
	@echo "    make build-all           Full workspace (needs libseat/libinput/etc)"
	@echo ""
	@echo "  Docker:"
	@echo "    make dev-build           Build the dev Docker image"
	@echo "    make dev                 Enter the dev container interactively"
	@echo ""
	@echo "  Keyboard shortcuts in shell window:"
	@echo "    Space    → Select (command palette toggle)"
	@echo "    Enter    → Start  (app switcher)"
	@echo "    Tab      → L2 trigger (radial menu)"
	@echo "    Esc      → B      (dismiss / back)"
	@echo "    A        → A      (confirm)"
	@echo "    Arrow keys → D-pad navigation"
	@echo ""

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# torchform-shell only (no hardware libs needed — works natively on any desktop)
check:
	$(CARGO) check -p torchform-shell

build: build-shell

build-shell:
	$(CARGO) build -p torchform-shell

# Full workspace — requires libseat, libinput, libgbm, libdrm on the host.
# Use Docker (make dev-build + make dev) if those are not installed.
check-all:
	$(CARGO) check --workspace

build-all:
	$(CARGO) build --workspace

build-release:
	$(CARGO) build -p torchform-shell --release

build-release-all:
	$(CARGO) build --workspace --release

# ---------------------------------------------------------------------------
# Run — shell UI (primary test target; no compositor or hardware needed)
# ---------------------------------------------------------------------------

# Emulator mode: single window showing both displays in a hardware frame (default)
run-emulator: build-shell
	$(CARGO) run -p torchform-shell

run-shell: run-emulator   # alias

run-shell-radial: build-shell
	$(CARGO) run -p torchform-shell -- --demo radial

run-shell-switcher: build-shell
	$(CARGO) run -p torchform-shell -- --demo switcher

run-shell-idle: build-shell
	$(CARGO) run -p torchform-shell -- --demo idle

# Standalone: two separate windows (mirrors the physical device)
run-standalone: build-shell
	$(CARGO) run -p torchform-shell -- --standalone

run-standalone-radial: build-shell
	$(CARGO) run -p torchform-shell -- --standalone --demo radial

# ---------------------------------------------------------------------------
# Run — compositor (Winit backend, nested inside your DE)
# ---------------------------------------------------------------------------
run-compositor: build
	TORCHFORM_BACKEND=winit RUST_LOG=debug $(CARGO) run -p torchform-compositor

# ---------------------------------------------------------------------------
# Docker dev environment
# ---------------------------------------------------------------------------

# Allow X11 connections from Docker (run once per session)
xhost-allow:
	xhost +local:docker

dev-build:
	docker build -t $(DOCKER_IMAGE) .devcontainer/

dev: dev-build xhost-allow
	$(DOCKER_RUN) bash

# Run the shell UI from inside Docker (for systems without native Rust)
dev-run-shell: dev-build xhost-allow
	$(DOCKER_RUN) bash -c "cargo build -p torchform-shell && \
	    RUST_LOG=debug cargo run -p torchform-shell"

dev-run-compositor: dev-build xhost-allow
	$(DOCKER_RUN) bash -c "cargo build -p torchform-compositor && \
	    TORCHFORM_BACKEND=winit RUST_LOG=debug cargo run -p torchform-compositor"

# ---------------------------------------------------------------------------
# Mock input sender — sends fake gamepad events to the inputd socket
# ---------------------------------------------------------------------------
send-input:
	python3 scripts/send-input.py

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	$(CARGO) clean

clean-docker:
	docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
	docker volume rm torchform-cargo-registry torchform-cargo-git 2>/dev/null || true
