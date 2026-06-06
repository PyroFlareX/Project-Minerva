# MinervaOS

Custom Linux OS and desktop environment for the Minerva Console (Project Minerva) —
a CM5-based clamshell handheld with controller input, dual displays, and a
power-user-focused workspace shell.

## Quick Start

### Prerequisites

Open this repo in VS Code. When prompted, click **"Reopen in Container"**.
The devcontainer builds automatically and runs `scripts/setup.sh` once.
That's it — all tooling is inside the container.

> On Windows: requires Docker Desktop + WSL2 backend.  
> On Linux: requires Docker (or Podman with the VS Code devcontainer extension).

### Build

```bash
make build        # Cross-compile all crates for ARM64
make image        # Build full MinervaOS disk image (takes a few minutes)
```

### Test in QEMU

```bash
make run          # Launch QEMU ARM64 VM (works on Windows + Linux)
make run-kvm      # Same with KVM acceleration (Linux only, much faster)
make ssh          # SSH into the running VM (user: user / minervaos)
```

### Deploy to CM5 IO Board

1. Edit `.env` (created automatically, gitignored):

   ```
   CM5_IP=10.0.0.XX
   ```

2. Flash a base MinervaOS image to an SD card or eMMC once (use `make image`).
3. After that, for iterative development:

   ```bash
   make deploy-bins   # Push only updated binaries over SSH (fast)
   make deploy        # Push binaries + OS overlays
   ```

## Project Structure

```
minervaos/
├── .devcontainer/       # Docker-based dev environment (auto-setup)
├── .vscode/             # Tasks and extension recommendations
├── crates/
│   ├── minerva-compositor/ # Smithay Wayland compositor
│   ├── minerva-shell/      # Slint UI shell (home screen, launcher)
│   ├── minerva-workspaced/ # Workspace manager daemon
│   └── minerva-inputd/     # Input mapping daemon (trackpad, controller)
├── os/
│   ├── build.sh         # Rootfs + disk image builder (Devuan base)
│   └── overlays/        # Files rsync'd onto rootfs at image build time
├── qemu/
│   ├── launch.sh        # QEMU launcher
│   └── vars.sh          # QEMU config variables
├── scripts/
│   └── setup.sh         # One-time dev environment setup
├── Cargo.toml           # Rust workspace root
└── Makefile             # All build targets
```

## Workspace IPC Protocol

`minerva-workspaced` listens on `/run/minerva/workspaced.sock`.
Protocol: newline-delimited JSON.
See `crates/minerva-workspaced/src/workspace.rs` for the full message schema.

## Default Credentials (QEMU / fresh image)

| Account | Password |
|---------|----------|
| user    | password   |
| root    | password   |

Change these before deploying to real hardware.
