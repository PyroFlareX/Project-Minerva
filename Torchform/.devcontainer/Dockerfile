# =============================================================================
# Torchform Dev Container
#
# Builds x86_64 native binaries (not cross-compiled) so you can run the
# shell UI and compositor on your desktop for testing.
#
# Display: supports both X11 (via DISPLAY socket) and Wayland (via
# WAYLAND_DISPLAY socket). The Makefile passes the right env vars.
# =============================================================================

FROM debian:bookworm-slim

# ---------------------------------------------------------------------------
# System build dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential pkg-config curl git ca-certificates \
    # Slint / Winit window system dependencies
    libx11-dev libx11-xcb-dev \
    libevdev-dev \
    libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libxkbcommon-dev libxkbcommon-x11-dev \
    libwayland-dev libwayland-egl1 \
    libgl1-mesa-dev libegl1-mesa-dev \
    libfontconfig1-dev libfreetype6-dev \
    # Smithay compositor dependencies
    libinput-dev libudev-dev libgbm-dev libdrm-dev \
    libseat-dev \
    # Font rendering (used by Slint)
    fonts-dejavu-core fonts-liberation \
    # uinput (for inputd virtual gamepad — not needed for shell UI test)
    # Input simulation tool
    python3 \
    # Conveniences
    less vim-tiny gosu \
  && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Non-root user + Cargo/Rustup directories (created as root, owned by dev)
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash dev \
    && mkdir -p /usr/local/cargo /usr/local/rustup \
    && chown dev:dev /usr/local/cargo /usr/local/rustup

USER dev
ENV HOME=/home/dev
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:$PATH

# ---------------------------------------------------------------------------
# Rust stable toolchain (x86_64-unknown-linux-gnu — native host)
# ---------------------------------------------------------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --default-toolchain stable \
    && rustup component add rust-analyzer clippy rustfmt

WORKDIR /workspace

# ---------------------------------------------------------------------------
# Entrypoint: fix cargo volume ownership (named volumes mount as root)
# ---------------------------------------------------------------------------
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
