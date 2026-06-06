# =============================================================================
# MinervaOS — top-level Makefile
# =============================================================================

-include .env

IMAGE      ?= minervaos.img
IMAGE_SIZE ?= 4G
CM5_IP     ?= 192.168.1.100
CM5_USER   ?= user
QEMU_MEM   ?= 8G
QEMU_SMP   ?= 4
SSH_PORT   ?= 2222

TARGET  := aarch64-unknown-linux-musl
BINS    := minerva-compositor minerva-shell minerva-workspaced minerva-inputd
BIN_DIR    := target/$(TARGET)/release

.PHONY: all build image run run-headless run-vnc run-kvm ssh deploy deploy-bins \
        clean clean-all check-deps help

# Default
all: build

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "  MinervaOS build targets"
	@echo ""
	@echo "  make build        Cross-compile all crates for aarch64-musl"
	@echo "  make image        Build full MinervaOS disk image (needs sudo)"
	@echo "  make run          Launch QEMU ARM64 VM (SDL display)"
	@echo "  make run-headless Launch QEMU headless (serial console, no GPU)"
	@echo "  make run-vnc      Launch QEMU with VNC display on port 5900"
	@echo "  make run-kvm      Launch QEMU with KVM (Linux host only)"
	@echo "  make ssh          SSH into running QEMU VM"
	@echo "  make deploy       rsync binaries + overlays to CM5"
	@echo "  make deploy-bins  rsync binaries only (faster)"
	@echo "  make check-deps   Verify all required tools are present"
	@echo "  make clean        Remove Rust build artifacts"
	@echo "  make clean-all    Remove build artifacts + disk image"
	@echo ""
	@echo "  Variables (override in .env or on command line):"
	@echo "    CM5_IP=$(CM5_IP)   CM5_USER=$(CM5_USER)"
	@echo "    IMAGE=$(IMAGE)     IMAGE_SIZE=$(IMAGE_SIZE)"
	@echo "    QEMU_MEM=$(QEMU_MEM)     QEMU_SMP=$(QEMU_SMP)"
	@echo ""

# ---------------------------------------------------------------------------
# check-deps
# ---------------------------------------------------------------------------
check-deps:
	@echo "▸ Checking dependencies..."
	@command -v aarch64-linux-musl-gcc >/dev/null \
		|| (echo "  MISSING: aarch64-linux-musl-gcc (musl cross toolchain)" && exit 1)
	@echo "  ✓ aarch64-linux-musl-gcc"
	@command -v qemu-system-aarch64 >/dev/null \
		|| (echo "  MISSING: qemu-system-aarch64" && exit 1)
	@echo "  ✓ qemu-system-aarch64"
	@rustup target list --installed | grep -q "$(TARGET)" \
		|| (echo "  MISSING: run 'rustup target add $(TARGET)'" && exit 1)
	@echo "  ✓ Rust target: $(TARGET)"
	@echo "  All deps OK."

# ---------------------------------------------------------------------------
# build — cross-compile all crates
# ---------------------------------------------------------------------------
build:
	@echo "▸ Building MinervaOS crates for $(TARGET)..."
	cargo build --release --target $(TARGET)
	@echo "  ✓ Build complete"

# ---------------------------------------------------------------------------
# image — build full OS disk image
# ---------------------------------------------------------------------------
image: build
	@echo "▸ Building MinervaOS disk image..."
	sudo IMAGE=$(IMAGE) IMAGE_SIZE=$(IMAGE_SIZE) bash os/build.sh $(IMAGE) $(IMAGE_SIZE)

# ---------------------------------------------------------------------------
# run — launch QEMU (no KVM, works everywhere)
# ---------------------------------------------------------------------------
run:
	@IMAGE=$(IMAGE) QEMU_MEM=$(QEMU_MEM) QEMU_SMP=$(QEMU_SMP) \
		SSH_PORT=$(SSH_PORT) bash qemu/launch.sh

# ---------------------------------------------------------------------------
# run-headless — no display, serial console on stdio (use inside devcontainer)
# ---------------------------------------------------------------------------
run-headless:
	@IMAGE=$(IMAGE) QEMU_MEM=$(QEMU_MEM) QEMU_SMP=$(QEMU_SMP) \
		SSH_PORT=$(SSH_PORT) bash qemu/launch.sh --headless

# ---------------------------------------------------------------------------
# run-vnc — virtio-gpu + VNC on port 5900 (for compositor testing)
# ---------------------------------------------------------------------------
run-vnc:
	@IMAGE=$(IMAGE) QEMU_MEM=$(QEMU_MEM) QEMU_SMP=$(QEMU_SMP) \
		SSH_PORT=$(SSH_PORT) bash qemu/launch.sh --vnc

# ---------------------------------------------------------------------------
# run-kvm — launch QEMU with KVM acceleration (Linux host only)
# ---------------------------------------------------------------------------
run-kvm:
	@IMAGE=$(IMAGE) QEMU_MEM=$(QEMU_MEM) QEMU_SMP=$(QEMU_SMP) \
		SSH_PORT=$(SSH_PORT) bash qemu/launch.sh --kvm

# ---------------------------------------------------------------------------
# ssh — connect to running QEMU VM
# ---------------------------------------------------------------------------
ssh:
	ssh -p $(SSH_PORT) \
	    -o StrictHostKeyChecking=no \
	    -o UserKnownHostsFile=/dev/null \
	    $(CM5_USER)@localhost

# ---------------------------------------------------------------------------
# deploy — push everything to CM5 IO Board
# ---------------------------------------------------------------------------
deploy: build
	@echo "▸ Deploying to CM5 at $(CM5_IP)..."
	rsync -avz --progress \
		$(addprefix $(BIN_DIR)/,$(BINS)) \
		os/overlays/ \
		$(CM5_USER)@$(CM5_IP):/
	@echo "  ✓ Deploy complete"

# ---------------------------------------------------------------------------
# deploy-bins — push binaries only (faster iteration)
# ---------------------------------------------------------------------------
deploy-bins: build
	@echo "▸ Deploying binaries to CM5 at $(CM5_IP)..."
	rsync -avz --progress \
		$(addprefix $(BIN_DIR)/,$(BINS)) \
		$(CM5_USER)@$(CM5_IP):/usr/local/bin/
	@echo "  ✓ Binaries deployed"

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------
clean:
	cargo clean

clean-all: clean
	rm -f $(IMAGE)
