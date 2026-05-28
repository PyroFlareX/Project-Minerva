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
	@echo "  Device (Minerva):"
	@echo "    make remote-vnc          Run shell on device, view via VNC (gvncviewer)"
	@echo "    make remote-vnc-kill     Kill remote cage/wayvnc and local tunnel"
	@echo "    make remote-build        Sync + build on device natively"
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

# ---------------------------------------------------------------------------
# Minerva device streaming
# ---------------------------------------------------------------------------
MINERVA_HOST ?= Minerva

.PHONY: stream-dev stream-dev-remote remote-build remote-test setup-local
setup-local:
	@bash scripts/setup-local.sh

stream-dev:
	@bash scripts/stream-dev-local.sh

# Run the capture+stream pipeline on the device (SSH).
# Useful for testing the device side without the local emulator.
stream-dev-remote:
	@rsync -avz scripts/stream-dev-remote.sh $(MINERVA_HOST):~/stream-dev-remote.sh
	@ssh $(MINERVA_HOST) "sh ~/stream-dev-remote.sh"

# Build torchform-shell for aarch64-musl, copy the binary and config files to
# the device.  Does not start any streaming — just deploys and smoke-tests.
# Sync source to the device and build natively (avoids cross-compilation).
# Binary ends up at ~/torchform-dev/target/release/torchform-shell.
remote-build:
	rsync -avz --exclude target/ --exclude .git/ \
	    . $(MINERVA_HOST):~/torchform-dev/
	ssh -t $(MINERVA_HOST) "cd ~/torchform-dev && PATH=\"\$$HOME/.cargo/bin:\$$PATH\" RUSTFLAGS=\"-C target-feature=-crt-static\" cargo build --release -p torchform-shell"

remote-test:
	cross build --target aarch64-unknown-linux-musl --release -p torchform-shell
	rsync -avz target/aarch64-unknown-linux-musl/release/torchform-shell \
	    $(MINERVA_HOST):~/torchform
	rsync -avz scripts/stream-dev-remote.sh $(MINERVA_HOST):~/stream-dev-remote.sh
	rsync -avz config/ $(MINERVA_HOST):~/.config/torchform/
	ssh $(MINERVA_HOST) "~/torchform --help 2>&1 | head -3 || echo '[remote-test] binary present'"

# ---------------------------------------------------------------------------
# Remote VNC — run shell on device via cage+wayvnc, view locally via gvncviewer
#   make remote-vnc              connect to Minerva (default)
#   make remote-vnc MINERVA_HOST=MinervaLocal
# ---------------------------------------------------------------------------
VNC_PORT ?= 5900

.PHONY: remote-vnc remote-vnc-kill

remote-vnc:
	@echo ">> Killing any stale cage/wayvnc on $(MINERVA_HOST) and local tunnel..."
	-ssh $(MINERVA_HOST) "pkill -9 -f wayvnc; pkill -9 -f cage; sleep 2; rm -rf /tmp/xdg-vnc" 2>/dev/null; true
	-pkill -f "ssh -L $(VNC_PORT)" 2>/dev/null; true
	@sleep 1
	@echo ">> Starting cage + wayvnc on $(MINERVA_HOST)..."
	ssh $(MINERVA_HOST) "bash -c ' \
	    export XDG_RUNTIME_DIR=/tmp/xdg-vnc; \
	    rm -rf \$$XDG_RUNTIME_DIR; \
	    mkdir -p \$$XDG_RUNTIME_DIR && chmod 700 \$$XDG_RUNTIME_DIR; \
	    export WLR_BACKENDS=headless; \
	    export WLR_HEADLESS_OUTPUTS=1; \
	    export DISPLAY=; \
	    SLINT_BACKEND=winit-software cage -d -- ./torchform-dev/target/release/torchform-shell & \
	    CAGE_PID=\$$!; \
	    sleep 2; \
	    WAYLAND_DISPLAY=wayland-0 wlr-randr --output HEADLESS-1 --custom-mode 768x950 2>/dev/null || true; \
	    sleep 1; \
	    if kill -0 \$$CAGE_PID 2>/dev/null; then \
	        WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/tmp/xdg-vnc \
	        wayvnc 127.0.0.1 $(VNC_PORT); \
	    else \
	        echo "ERROR: cage exited early"; \
	    fi \
	'" &
	@echo ">> Waiting for VNC to start..."
	@sleep 5
	@echo ">> Opening SSH tunnel and gvncviewer..."
	ssh -L $(VNC_PORT):localhost:$(VNC_PORT) $(MINERVA_HOST) -N &
	@sleep 1
	gvncviewer localhost::$(VNC_PORT)

remote-vnc-kill:
	-ssh $(MINERVA_HOST) "pkill -f wayvnc; pkill -f cage" 2>/dev/null; true
	-pkill -f "ssh -L $(VNC_PORT)" 2>/dev/null; true

# ── QuickShell demo ───────────────────────────────────────────────────────────
.PHONY: deploy-hdmi hdmi-restart remote-vnc-qs remote-vnc-qs-kill

# Sync QML + C source to Minerva, compile gamepad-map there, restart on HDMI.
deploy-hdmi:
	@echo ">> Syncing demo-quickshell to $(MINERVA_HOST)..."
	ssh $(MINERVA_HOST) "mkdir -p ~/projects/demo-quickshell"
	rsync -avz --exclude='*.o' --exclude=gamepad-map demo-quickshell/. \
	    $(MINERVA_HOST):~/projects/demo-quickshell/
	@echo ">> Compiling gamepad-map on $(MINERVA_HOST)..."
	ssh $(MINERVA_HOST) "gcc -O2 -o ~/projects/demo-quickshell/gamepad-map \
	    ~/projects/demo-quickshell/gamepad-map.c && echo '   gamepad-map OK'"

hdmi-restart: deploy-hdmi
	@echo ">> Restarting demo on HDMI..."
	-ssh $(MINERVA_HOST) "pkill -9 -x quickshell; pkill -9 -x sway; \
	    pkill -9 -f demo-quickshell/gamepad-map" 2>/dev/null; true
	ssh $(MINERVA_HOST) \
	    "nohup setsid bash ~/projects/demo-quickshell/start-hdmi.sh \
	     </dev/null >/tmp/start-hdmi.log 2>&1 &"
	@echo ">> Running — tail logs: ssh $(MINERVA_HOST) tail -f /tmp/quickshell-hdmi.log"

remote-vnc-qs:
	@echo ">> Killing stale quickshell/wayvnc on $(MINERVA_HOST)..."
	-ssh $(MINERVA_HOST) "pkill -9 -f wayvnc; pkill -9 -f quickshell; pkill -9 -f 'sway.*torchform'; rm -rf /tmp/xdg-qs-vnc" 2>/dev/null; true
	-pkill -f "ssh -L $(VNC_PORT)" 2>/dev/null; true
	@sleep 1
	@echo ">> Syncing demo files to $(MINERVA_HOST)..."
	ssh $(MINERVA_HOST) "mkdir -p ~/projects/demo-quickshell"
	scp -r demo-quickshell/. $(MINERVA_HOST):~/projects/demo-quickshell/
	@echo ">> Starting QuickShell demo on $(MINERVA_HOST)..."
	ssh $(MINERVA_HOST) "VNC_PORT=$(VNC_PORT) bash ~/projects/demo-quickshell/start.sh" &
	@echo ">> Waiting for wayvnc to start..."
	@sleep 10
	@echo ">> Opening SSH tunnel and viewer..."
	ssh -L $(VNC_PORT):localhost:$(VNC_PORT) $(MINERVA_HOST) -N &
	@sleep 1
	gvncviewer localhost::$(VNC_PORT)

remote-vnc-qs-kill:
	-ssh $(MINERVA_HOST) "pkill -f wayvnc; pkill -f quickshell; pkill -f 'sway.*torchform'" 2>/dev/null; true
	-pkill -f "ssh -L $(VNC_PORT)" 2>/dev/null; true
