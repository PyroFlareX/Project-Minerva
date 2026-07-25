# Minerva Storage and Data Manual

This document describes the storage layout deployed on the physical Minerva CM5, where persistent files belong, and how to verify the system after boot. It was reconciled against the live device on 2026-07-22.

The live system is authoritative for operations. `CONTEXT.md` and `README.MD` describe the intended end-state architecture; several of those features are not deployed yet. See [Design versus deployed state](#design-versus-deployed-state).

## System identity

| Item | Deployed value |
|---|---|
| Hostname | `Minerva` |
| Architecture | `aarch64` |
| Distribution | Alpine Linux 3.24.0 |
| Kernel | Linux 6.18.35-0-rpi |
| Login user | `pyros` (`/home/pyros`) |
| OS device | CM5 eMMC, `/dev/mmcblk0` |
| User-data device | NVMe, `/dev/nvme0n1` |
| User-data encryption | LUKS2 mapping named `minerva-data` |
| User-data filesystem | Btrfs, label `minerva-data` |

## Storage stack

```text
CM5 eMMC /dev/mmcblk0 (14.5 GiB)
├── /dev/mmcblk0p1  300 MiB  vfat  → /boot
└── /dev/mmcblk0p2  14.2 GiB ext4  → /

NVMe /dev/nvme0n1 (1.863 TiB)
└── /dev/nvme0n1p1
    └── LUKS2 → /dev/mapper/minerva-data
        └── Btrfs label minerva-data
            ├── @home         → /home
            ├── @projects     → /home/pyros/projects
            ├── @swap         → /swap
            ├── @snapshots    → /.snapshots
            ├── @media        → /home/pyros/media
            ├── @applications → /opt/applications
            └── @games        → /home/pyros/games
```

The eMMC root is currently a writable ext4 filesystem. Keep large or irreplaceable data on the encrypted NVMe mounts, not on `/`.

## Boot and mount order

1. The CM5 boots from the eMMC boot partition mounted at `/boot`.
2. `/dev/mmcblk0p2` becomes the writable ext4 root filesystem.
3. OpenRC starts `dmcrypt` in the `boot` runlevel.
4. `/etc/conf.d/dmcrypt` opens the NVMe LUKS2 partition as `/dev/mapper/minerva-data` using the root-only key file configured at `/etc/crypto_keyfile.bin`.
5. `localmount` processes `/etc/fstab` and mounts the Btrfs subvolumes.
6. `/run`, `/tmp`, and `/dev/shm` are RAM-backed and must be treated as ephemeral.

Never copy, print, or commit `/etc/crypto_keyfile.bin`. Its deployed permissions are `0600 root:root`.

### Encryption configuration

The deployed configuration identifies the encrypted container as:

```text
mapper name: minerva-data
LUKS UUID:   387cd90b-2f7d-4463-8f59-02864948145a
key file:    /etc/crypto_keyfile.bin
```

These identifiers document the current device, not a provisioning invariant. Replacements and reformatting produce new UUIDs; update `/etc/crypttab`, `/etc/conf.d/dmcrypt`, and `/etc/fstab` together.

## Persistent mount layout

| Btrfs subvolume | ID | Mount point | Owner | Intended contents |
|---|---:|---|---|---|
| `@home` | 256 | `/home` | `root:root`; user directories owned by their users | User profiles and default persistent files |
| `@projects` | 257 | `/home/pyros/projects` | `pyros:pyros` | Source trees and active development projects |
| `@swap` | 258 | `/swap` | `root:root` | Swapfile storage only |
| `@snapshots` | 259 | `/.snapshots` | `root:root` | Root-managed Btrfs snapshots |
| `@media` | 260 | `/home/pyros/media` | `pyros:pyros` | Downloads, documents, music, video, and other media |
| `@applications` | 261 | `/opt/applications` | `pyros:root` | Large application payloads; currently contains Flatpak data |
| `@games` | 262 | `/home/pyros/games` | `pyros:pyros` | Game installs, assets, and prefixes |

All regular data subvolumes use `compress=zstd` and `ssd`. The filesystem currently holds about 35 GiB with roughly 1.8 TiB available.

### Placement rules

- **Operating-system files:** `/`, `/usr`, `/etc`, and `/var` remain on the eMMC. Do not use these paths for large user payloads.
- **User configuration:** `~/.config`.
- **User application data:** `~/.local/share`.
- **User state:** `~/.local/state`.
- **Regenerable cache:** `~/.cache`.
- **User executables:** `~/.local/bin`.
- **Development trees:** `~/projects`.
- **Media and downloads:** `~/media`.
- **Games:** `~/games`.
- **Large managed applications:** `/opt/applications`.
- **Temporary files:** `/tmp` or `/run`; both disappear at reboot.
- **System-wide configuration:** `/etc`; currently persistent on eMMC, but expected to move behind the planned immutable-root overlay model.

Do not create new application-specific top-level directories when an XDG location or an existing dedicated mount fits.

## XDG user layout

The active zsh environment defines:

```sh
XDG_CONFIG_HOME="$HOME/.config"
XDG_DATA_HOME="$HOME/.local/share"
XDG_STATE_HOME="$HOME/.local/state"
XDG_CACHE_HOME="$HOME/.cache"
```

All four are under the encrypted `@home` subvolume. Configuration and state survive reboot; cache may be deleted and rebuilt.

### Home-directory pollution policy

Minerva keeps `$HOME` limited to user-facing directories and the standard XDG roots. Tool-specific dot directories should be relocated with supported environment variables instead of accumulating as `~/.<tool>`.

| Tool | Environment | Persistent location |
|---|---|---|
| Claude | `CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"` | `~/.config/claude` |
| Cargo | `CARGO_HOME="$XDG_DATA_HOME/cargo"` | `~/.local/share/cargo` |
| Rustup | `RUSTUP_HOME="$XDG_DATA_HOME/rustup"` | `~/.local/share/rustup` |
| OMP config | `PI_CONFIG_DIR=".config/omp"` | `~/.config/omp` |
| OMP agent | `PI_CODING_AGENT_DIR="$HOME/.config/omp/agent-home"` | `~/.config/omp/agent-home` |
| OMP native data | XDG discovery | `~/.local/share/omp/natives` |
| npm | `NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"` | `~/.config/npm/npmrc` |
| Conan | `CONAN_HOME="$XDG_DATA_HOME/conan2"` | `~/.local/share/conan2` |
| GnuPG | `GNUPGHOME="$XDG_DATA_HOME/gnupg"` | `~/.local/share/gnupg` |

Define these variables in `~/.config/zsh/.zshenv` so login, interactive, and non-interactive zsh processes agree. Before deleting a legacy dot directory, merge unique persistent files into its XDG destination, verify the tool in a fresh login shell, and only then remove the old directory. Do not retain compatibility symlinks unless a tool has no supported directory override; symlinks leave the home-root namespace polluted and can hide regressions.

Alpine's `/etc/zsh/zprofile` sources `/etc/profile`, which resets `PATH` during login. `~/.config/zsh/.zprofile` restores the Minerva user paths afterward:

```sh
$HOME/.local/bin
$HOME/.local/share/cargo/bin
$HOME/userpkgs/usr/bin
```

Put persistent login-shell PATH changes in `~/.config/zsh/.zprofile`, not only in `.zshenv`.

## Torchform files

Torchform merges configuration in this order, highest priority first:

1. `~/.config/torchform/config.toml`
2. `/etc/torchform/config.toml`
3. Repository fallback `Torchform/config/torchform.toml`
4. Built-in defaults

Related locations:

| Path | Purpose |
|---|---|
| `~/.config/torchform/config.toml` | User shell and application overrides |
| `~/.config/torchform/input.toml` | Device input configuration |
| `~/.config/torchform/keybinds.toml` | Optional user keybind overrides |
| `~/.config/torchform/themes/` | User themes |
| `~/.local/share/torchform` | Default persistent Torchform application data |
| `/etc/torchform` | System defaults |
| `/run/torchform` | Runtime sockets/state when used; ephemeral |
| `~/torchform-dev` | On-device development checkout, not production state |

The configured `general.data_dir` defaults to `~/.local/share/torchform`. Repository config is a development fallback and must not be treated as the live user-data directory.

## OMP files

The installed musl binary lives at:

```text
/home/pyros/.local/bin/omp
```

Minerva relocates OMP's config, databases, sessions, and logs into the XDG config tree:

```sh
PI_CONFIG_DIR=".config/omp"
PI_CODING_AGENT_DIR="$HOME/.config/omp/agent-home"
```

`PI_CONFIG_DIR` is a directory name relative to `$HOME`, not an absolute path. The explicit non-default `PI_CODING_AGENT_DIR` keeps agent databases and state physically under `~/.config/omp`; without it, OMP 17.0.8 redirects the default agent's data into `$XDG_DATA_HOME/omp` as soon as that XDG directory exists.

`omp config path` must therefore print:

```text
/home/pyros/.config/omp/agent-home
```

Do not set `PI_CONFIG_DIR="$HOME/.config/omp"`. OMP 17.0.8 prefixes absolute values with the home directory and previously produced the invalid path `/home/pyros/home/pyros/.config/omp/agent`.

The native-addon loader uses `$XDG_DATA_HOME/omp/natives` when `$XDG_DATA_HOME/omp` exists and otherwise falls back to `~/.omp/natives`. Minerva keeps the XDG data directory present so OMP does not recreate `~/.omp`; native payloads are application data rather than dotfile configuration.

| Path | Purpose |
|---|---|
| `~/.config/omp/agent-home/agent.db` | Credentials, jobs, cache metadata, threads, usage, and agent state |
| `~/.config/omp/agent-home/history.db` | History index |
| `~/.config/omp/agent-home/models.db` | Model catalog/cache database |
| `~/.config/omp/agent-home/config.yml` | Agent configuration |
| `~/.config/omp/agent-home/models.yml` | Local model overrides |
| `~/.config/omp/agent-home/keybindings.yml` | OMP keybindings |
| `~/.config/omp/agent-home/sessions/` | Session transcripts |
| `~/.config/omp/agent-home/blobs/` | Session attachments and generated blobs |
| `~/.config/omp/agent-home/memories/` | Project memory |
| `~/.config/omp/agent-home/managed-skills/` | Managed skills |
| `~/.config/omp/agent-home/cache/` | Regenerable agent-local caches |
| `~/.local/share/omp/natives/<version>/` | Native addon extracted by the release binary |
| `~/.config/omp/logs/` | OMP logs outside the agent home |

### Moving OMP state

OMP databases use SQLite WAL mode. Do not copy only a live `.db` file and assume it contains current data. Use one of these approaches:

1. Stop every OMP process, then copy each `.db` together with its matching `-wal` and `-shm` files.
2. Preferably, create a consistent backup with SQLite's backup API, then copy the backup as the destination `.db`.

After migration:

```sh
omp config path
omp usage
omp models --help
```

`omp usage` reporting `No credentials found` while the source database contains credentials usually means OMP is opening a different agent directory. Check `PI_CONFIG_DIR`, `PI_CODING_AGENT_DIR`, and `omp config path` before copying the database again.

## Runtime and temporary data

| Path | Backing | Lifetime | Use |
|---|---|---|---|
| `/run` | tmpfs, about 1.6 GiB | Reboot | PID files, sockets, service runtime state |
| `/run/minerva` | tmpfs directory created by provisioning | Reboot | Minerva daemon sockets such as `workspaced.sock` |
| `/tmp` | tmpfs, about 3.9 GiB | Reboot | Build/test scratch files only |
| `/dev/shm` | tmpfs, about 3.9 GiB | Reboot | Shared memory |

Never store credentials, source-of-truth configuration, session history, or user documents only in these locations.

## Snapshots

`/.snapshots` is a dedicated root-owned Btrfs subvolume. Existing snapshot names follow forms such as:

```text
home-YYYYMMDD-HHMMSS
projects-YYYYMMDD-HHMMSS
media-YYYYMMDD-HHMMSS
games-YYYYMMDD-HHMMSS
applications-YYYYMMDD-HHMMSS
```

No snapshot scheduler is defined in this repository. Do not assume snapshots are current or automatic. Snapshot creation, deletion, and restoration require elevated privileges and must preserve subvolume boundaries.

A snapshot is not a backup: it shares the same NVMe device and does not protect against device loss or LUKS/key loss.

## Swap status

`/etc/fstab` declares `/swap/swapfile`, but `/proc/swaps` was empty during the live inspection. Swap is therefore configured but not currently active.

The `@swap` fstab entry requests `nodatacow`, but the live Btrfs mount report still shows filesystem compression inherited from the first mount. Before enabling the swapfile, verify that the file itself is NOCOW and valid for Btrfs; do not rely on the subvolume mount option alone.

Check with:

```sh
cat /proc/swaps
mount | grep ' on /swap '
```

## Operational checks

### Normal user checks

```sh
# Mounted filesystems and capacity
df -hT
mount

# Block-device topology (BusyBox lsblk has no util-linux -o option)
lsblk

# Swap status
cat /proc/swaps

# Correct OMP state path and credential visibility
omp config path
omp usage

# XDG and PATH state in a fresh login shell
zsh -lic 'printf "%s\n" "$PATH"; command -v omp'
```

### Root checks

```sh
# LUKS mapping
doas cryptsetup status minerva-data

# Btrfs filesystem and subvolumes
doas btrfs filesystem show /home
doas btrfs subvolume list /home

# Boot services
rc-status -a

# Configuration sources
cat /etc/crypttab
cat /etc/conf.d/dmcrypt
cat /etc/fstab
```

If `/home` is unavailable after boot, diagnose in this order:

1. Confirm `/dev/nvme0n1p1` exists.
2. Confirm `dmcrypt` started and `/dev/mapper/minerva-data` exists.
3. Confirm the key file exists with `0600 root:root` permissions.
4. Confirm the LUKS UUID in `crypttab` and `dmcrypt` matches the partition.
5. Run `mount -a` with elevated privileges and inspect the first error.
6. Do not reformat, run repair, or recreate subvolumes until the encryption and mount configuration have been ruled out.

## Design versus deployed state

The repository currently contains three distinct storage descriptions. They are not interchangeable:

| Source | Purpose | Current layout |
|---|---|---|
| Physical Minerva | Operational system | Writable ext4 eMMC root plus LUKS2/Btrfs NVMe subvolumes described above |
| `CONTEXT.md` / `README.MD` | Target architecture | 32 GiB eMMC, A/B dm-verity root, writable overlay, LUKS2 plus ZFS, `/data`, persistent `/var/log`, encrypted swap |
| `Project-Minerva-OS/os/build.sh` | QEMU/development image | Single ext4 root labeled `minervaos-root`, user `user`, no physical NVMe layout |
| `rpi-scripts/setup-fresh-alpine-install.sh` | Earlier physical provisioning | Creates `/data/workspaces` and `/data/projects` on rootfs pending a future ZFS/NVMe setup |

Important deployed differences:

- The installed eMMC is 14.5 GiB, not the documented 32 GiB target.
- Root is writable ext4; A/B slots, dm-verity, and overlayfs are not active.
- User data is Btrfs on LUKS2, not ZFS.
- The live account is `pyros`, not the design/build-script account `user`.
- There is no live `/data` mount.
- `/var/log` and `/var/lib/containers` are not separate NVMe mounts.
- Swap is declared but inactive.

When changing the deployed mount layout, update this manual and the provisioning/build sources together. Do not modify `CONTEXT.md` to describe an implementation shortcut as the final security design; instead, keep the distinction between current and target state explicit.
