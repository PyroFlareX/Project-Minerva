# CONTEXT.md — Minerva Project Design Reference

> **Last updated:** March 2026
> **Status:** Active development — hardware schematic + OS foundation + DE design phase
> **Naming:** Device = **Minerva**, OS = **Minerva OS**, Desktop Environment = **Torchform**

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Directory Structure](#2-directory-structure)
3. [Physical Design & Enclosure](#3-physical-design--enclosure)
4. [Compute Module — Raspberry Pi CM5](#4-compute-module--raspberry-pi-cm5)
5. [Custom Motherboard & PCB](#5-custom-motherboard--pcb)
6. [Display System](#6-display-system)
7. [Input System](#7-input-system)
8. [Storage Architecture](#8-storage-architecture)
9. [Power System](#9-power-system)
10. [Connectivity](#10-connectivity)
11. [Audio](#11-audio)
12. [NFC & RFID](#12-nfc--rfid)
13. [Optional Daughterboard — RF & Biometrics](#13-optional-daughterboard--rf--biometrics)
14. [Security Architecture](#14-security-architecture)
15. [Camera (Future)](#15-camera-future)
16. [GPIO Budget & Bus Allocation](#16-gpio-budget--bus-allocation)
17. [Minerva OS](#17-minerva-os)
18. [Torchform — Desktop Environment](#18-torchform--desktop-environment)
19. [Application Suite](#19-application-suite)
20. [Open Questions & Decisions Pending](#20-open-questions--decisions-pending)

---

## 1. Project Overview

Minerva is a custom clamshell handheld computing device built around the Raspberry Pi Compute Module 5. It combines a gaming controller form factor with a full Linux environment, dual displays, cellular connectivity, NFC/RFID capabilities, and a security-first architecture built on an immutable OS with hardware-backed encryption.

The device is not a game console — it is a general-purpose handheld computer designed for an unconventional input paradigm. Every layer of software, from compositor to application, is purpose-built for controller-style interaction without assuming a keyboard or precise pointer is available.

**Design lineage:** The New Nintendo 3DS (KTR-001, 2014) is the explicit aesthetic and ergonomic reference. Minerva matches its footprint almost exactly, adding thickness to accommodate the CM5 and a 5000mAh battery.

**Core philosophy:**
- The hardware serves the software vision, not the other way around.
- Specific component choices may change; the *purpose* of each subsystem is what matters.
- Minimize runtime overhead and toolkit friction across the entire stack.
- Security is structural, not bolted on — immutable root, hardware key storage, kill switches.

---

## 2. Directory Structure

```
Project Minerva/
├── Minerva Hardware/          # KiCad project — CM5 carrier board (CM5IO)
│   ├── CM5IO.kicad_sch        # Root schematic
│   ├── CM5IO.kicad_pcb        # PCB layout
│   ├── CM5_GPIO.kicad_sch     # GPIO sub-sheet
│   ├── CM5_HighSpeed.kicad_sch # MIPI DSI, CSI, PCIe, USB3
│   ├── PCIe-M2.kicad_sch     # M.2 NVMe slot
│   ├── CM5IO.kicad_prl       # Design rules
│   ├── CM5IOBOM.txt           # Bill of materials
│   ├── *.pretty/              # Footprint libraries
│   ├── *.3dshapes/            # 3D models
│   └── README.TXT
├── Minerva OS/                # Rust workspace — OS, compositor, apps
│   ├── .cargo/                # Cargo config (musl target, linker)
│   ├── .devcontainer/         # VS Code dev container for cross-compilation
│   ├── crates/                # Workspace member crates
│   ├── os/                    # OS-level config, overlays, packaging
│   ├── qemu/                  # QEMU scripts for aarch64 testing
│   ├── scripts/               # Build and deployment scripts
│   ├── Cargo.toml             # Workspace root
│   ├── Cargo.lock
│   ├── Makefile
│   └── README.md
├── Notes/                     # Design notes, references
├── rpi-scripts/               # Raspberry Pi setup and provisioning
│   └── setup-fresh-alpine-install.sh
├── CONTEXT.md                 # ← This file
└── Project Minerva.code-workspace
```

**Enclosure CAD** is in OnShape (cloud), project name "Project Minerva". Not stored in this repo.

---

## 3. Physical Design & Enclosure

### 3.1 Form Factor

Clamshell handheld. Two shells connected by a friction hinge. Closes flat for pocketing.

| Dimension | Value | Notes |
|-----------|-------|-------|
| Width | 145 mm | 2.5mm bezel beyond display on each side |
| Depth (closed) | 82 mm | Front-to-back when shut |
| Upper shell height | 10 mm | Houses upper display panel + backlight |
| Lower shell height | 20 mm | Houses PCB, battery, NVMe, all electronics |
| Total closed height | 30 mm | KTR-001 is 21.6mm — 8.4mm thicker for CM5 + battery |
| Shell wall thickness | 2 mm | PETG/ABS for prototypes; aluminum/magnesium for production |
| Corner roundedness | 30° | Ergonomic fillet angle, consistent with 3DS aesthetic |
| Hinge radius | 6 mm | Two barrel hinges, symmetric |
| Hinge edge distance | 35 mm | Center of hinge from side edges |
| Screw type | M1.6 (1.52mm) | Torx T4 or JIS Phillips recommended |

### 3.2 KTR-001 Design Reference

| Aspect | KTR-001 | Minerva |
|--------|---------|---------|
| Dimensions | 142 × 80.6 × 21.6mm | 145 × 82 × 30mm |
| Shell aesthetic | Removable faceplates, matte/gloss, coloured ABXY | 30° rounded corners, 2mm walls, coloured ABXY |
| Internal layout | Battery left, mainboard right, structural spine | Reproduced exactly — spine divides lower shell |
| Hinge | Two barrel, spring/friction, internal cable channel | Friction hinge, 6mm radius, carries DSI + sensor wires |
| Shoulders | L, R, ZL, ZR | L1, R1, L2, R2 — identical count |

### 3.3 Internal Layout

The lower shell is divided by a **central structural spine** running front-to-back:

- **Left zone:** Battery compartment. Full ~16mm internal depth available. Fits a 5000mAh LiPo pouch cell (~70×50×10mm).
- **Right zone:** Mainboard/electronics bay. CM5 module (~4.8mm tall) on 1.6mm carrier PCB, plus connectors and thermal solution.
- **Upper face region** (above both zones, below hinge): The 3.5" lower touchscreen sits here, spanning across both zones.

### 3.4 Hinge & Cable Routing

The hinge must carry through its internal channel:
- DSI ribbon cable (upper display)
- Hall effect sensor wire (lid open/close detection)
- (Future) MIPI CSI ribbon for rear camera

Friction hinge (torque hinge) preferred — holds the lid at any angle. Design hinge stop at 130°–140° maximum to protect flex cables from over-extension.

### 3.5 Ventilation

Vent slots modeled on the front-bottom edge of the lower shell. Place the CM5 SoC near this area. Consider a small 3010 or 3007 blower fan for active cooling if thermals require it. Passive-first design — fan is a fallback.

---

## 4. Compute Module — Raspberry Pi CM5

The CM5 is the SoM (System on Module) at the heart of the device. It plugs into the custom motherboard via a high-density connector.

### 4.1 Specifications

| Parameter | Value |
|-----------|-------|
| Variant | CM5 — 8GB LPDDR4X, 32GB eMMC |
| CPU | ARM Cortex-A76 quad-core, up to 2.4GHz |
| GPU | VideoCore VII — OpenGL ES 3.1, Vulkan 1.2 |
| eMMC | 32GB — OS partitions only |
| PCIe | Gen 2 ×1 — allocated to NVMe SSD |
| USB | 1× USB 3.0 (WWAN), 1× USB 2.0 (routed to USB-C) |
| Display | 2× MIPI DSI — upper 1080p + lower 3.5" touchscreen |
| Camera | 1× MIPI CSI — reserved for future rear camera |
| GPIO | 28 usable pins — shared across SPI, I2C, UART, digital |
| WiFi | 802.11ac (WiFi 5), 2.4/5GHz dual-band |
| Bluetooth | 5.0 BLE + Classic |
| Connector | Hirose DF40C-100DS-0.4V (0.4mm pitch) |

### 4.2 What the CM5 Does NOT Provide

The CM5 is a compute module, not a full board. The custom motherboard must provide:
- All power regulation (PMIC, battery charging, USB-PD)
- All physical connectors (USB-C, M.2 slots, display FPCs, audio, GPIO header)
- All peripheral ICs (secure element, NFC, audio codec, input MCU)
- ESD protection on all external-facing I/O
- Antenna routing for WiFi/BT (U.FL) and WWAN

---

## 5. Custom Motherboard & PCB

The carrier board is designed in **KiCad** (see `Minerva Hardware/` directory). It routes all CM5 I/O to the device's peripherals.

### 5.1 Critical Design Points

- **CM5 connector:** Hirose DF40C-100DS-0.4V — 0.4mm pitch, requires 4-layer minimum (6-layer recommended)
- **MIPI DSI:** Differential pairs, length-matched, 90Ω impedance controlled. Keep away from switching regulators.
- **USB 3.0:** SuperSpeed differential pairs, 90Ω impedance. Minimize vias on SS pairs.
- **PCIe (NVMe):** 85Ω differential, length-matched, AC coupling caps on TX pairs.
- **RF traces (NFC, WWAN antennas):** 50Ω microstrip, maintain ground plane clearance.
- **ESD protection:** TVS diodes on all external-facing I/O (USB-C, GPIO header, audio jack, NFC antenna).

### 5.2 Recommended PCB Stackup

| Layer | Purpose |
|-------|---------|
| 1 (Top) | Components and signals |
| 2 | Ground plane — unbroken, especially under RF and high-speed |
| 3 | Power planes (3.3V, 1.8V pours) |
| 4 (Bottom) | Signals, some components |

4-layer is minimum viable. 6-layer recommended for better signal integrity on MIPI DSI, USB 3.0, and PCIe.

### 5.3 USB-C Port Design

Single external USB-C port consolidates charging, data, and optional expansion.

| Function | Implementation |
|----------|---------------|
| Charging | USB Power Delivery — 5V/3A minimum, 9V/2A preferred |
| USB 2.0 data | Always available for keyboard, OTG peripherals |
| DP alt mode | Routed from CM5 HDMI via bridge chip (e.g. PTN3460) |
| Mux | TUSB1046 or HD3SS3220 for mode switching |
| PD controller | FUSB302 — handles negotiation independently of CM5 |

---

## 6. Display System

### 6.1 Upper Display — Primary

| Parameter | Value |
|-----------|-------|
| Size | 5.5" diagonal |
| Resolution | 1920×1080 (1080p) |
| Physical dimensions | 140mm wide × ~70mm tall |
| Aspect ratio | 16:9 landscape |
| PPI | ~393 (Retina-class) |
| Interface | MIPI DSI via FPC ribbon through hinge |
| Touch | **No.** Panel may physically support touch but it is not used as a touch input surface. Display-only. |

### 6.2 Lower Display — Secondary Touchscreen

| Parameter | Value |
|-----------|-------|
| Size | 3.5" diagonal |
| Resolution | 480×320 minimum, 640×480 preferred — anything ≥480p |
| Interface | MIPI DSI (second DSI port) + I2C for touch controller |
| Touch | **Yes — capacitive touchscreen.** This is the device's touch input surface. |
| Purpose | App content, on-screen keyboard, system info, radial menus, secondary app views |

### 6.3 Display Roles in Software

The compositor (Smithay) manages both displays as distinct outputs. The upper screen is the primary application viewport. The lower screen is a contextual companion — it shows different content depending on what is focused on the upper screen (e.g., a map app might show controls on the bottom, a text editor might show a virtual keyboard). This is architecturally similar to the Wii U GamePad or Nintendo DS, not a simple extended desktop.

---

## 7. Input System

### 7.1 Controller Layout

The input system mirrors a 3DS-style layout with key modifications: the left analog stick is replaced by a Cirque capacitive trackpad, and all buttons are scanned by a dedicated input microcontroller.

| Input | Type | Interface | Notes |
|-------|------|-----------|-------|
| Left trackpad | Cirque GlidePoint circular capacitive | SPI0 to CM5 | 35–40mm diameter. Replaces left analog stick. Emulates joystick axes via uinput daemon. |
| Right stick | Hall effect analog | I2C (TLV493D or AS5600) via input MCU | Full analog range. No mechanical wear or drift. |
| D-pad | 4-way digital | Input MCU GPIO | Spatial navigation in UI |
| A, B, X, Y | Digital face buttons | Input MCU GPIO | 14mm diameter caps, 14.5mm pitch center-to-center |
| L1, R1 | Digital shoulder buttons | Input MCU GPIO | Primary shoulders |
| L2, R2 | Analog (preferred) or digital triggers | Input MCU ADC | Radial menu layer activators. Analog preferred for gaming. |
| Start | Digital | Input MCU GPIO | App switcher |
| Select | Digital | Input MCU GPIO | Command palette |
| Lower touchscreen | Capacitive touch | I2C touch controller | Gestures, radial menu touch, secondary display interaction |

### 7.2 Input Microcontroller

A dedicated MCU handles button scanning, debouncing, and ADC rather than consuming CM5 GPIO directly.

| Parameter | Detail |
|-----------|--------|
| Purpose | Scan all digital buttons, D-pad, L2/R2 analog, right stick (via TLV493D I2C) |
| Candidates | RP2040 (cheap, well-documented) or STM32F0 series |
| Communication | I2C to CM5 as a custom peripheral, OR USB HID gamepad |
| What it does NOT do | Chord detection — that happens in software on the CM5 |

The **Cirque trackpad connects directly to CM5 SPI0**, not through the input MCU. It has its own mainline kernel driver (`cirque_pinnacle`).

### 7.3 Cirque GlidePoint Trackpad

| Parameter | Value |
|-----------|-------|
| Part | Cirque TM035035 (35mm) or TM040040 (40mm) |
| Interface | SPI (preferred for polling rate) |
| Kernel driver | `cirque_pinnacle` — mainline, no out-of-tree patches |
| Polling rate | Up to 500Hz on SPI |
| Modes | Standard coordinate mode (cursor), Anymeas mode (raw capacitive, lower latency) |
| Emulation | uinput virtual gamepad — joystick axis emulation with configurable mapping |

### 7.4 Input Grammar

This is the settled input language for the entire DE and all applications:

| Input | Action |
|-------|--------|
| Left pad (Cirque) | Cursor / navigation |
| D-pad | Spatial focus movement (up/down/left/right between UI elements) |
| A | Confirm / select |
| B | Back / cancel |
| L2 | Hold: radial menu layer 1 |
| R2 | Hold: radial menu layer 2 |
| L2 + R2 | Hold both: global system radial menu |
| Select | Command palette |
| Start | App switcher |
| L1 / R1 | Tile switching (in split-screen mode) |

**UI control types are strictly limited to:** sliders, checkboxes, and enumeration pickers. No dropdowns, no text fields requiring a keyboard (virtual keyboard on lower screen when text entry is needed).

**Input paradigm priority order:**
1. Radial menus and chorded button combos (primary)
2. Voice input via on-device STT (secondary)
3. Spatial/tab navigation with D-pad (fallback)

### 7.5 Tiling Model

- **Fullscreen-first** — every app launches fullscreen on the upper display
- **Optional horizontal split** — two apps side by side, no other split modes
- **No floating windows** — ever
- **L1/R1** switch focus between tiles when in split mode

---

## 8. Storage Architecture

### 8.1 eMMC (32GB, on CM5) — Boot & OS

The eMMC holds only the operating system. It is never used for user data.

| Partition | Purpose |
|-----------|---------|
| 1 — Bootloader | U-Boot, read-only, signed |
| 2 — Slot A | Minerva OS verified image (dm-verity, ~4GB) |
| 3 — Slot B | Recovery OS image (minimal, read-only, ~2GB) |
| 4 — Boot config | A/B selector flag, U-Boot environment |
| 5 — Overlay | Writable overlayfs layer for `/etc` and system config |

**Boot flow:** U-Boot verifies Slot A via dm-verity hash tree. If verification fails, automatic fallback to Slot B. Slot B is a minimal recovery environment capable of re-flashing Slot A, decrypting the NVMe for data recovery, and performing factory reset.

**Overlay partition:** A small writable partition provides an overlayfs upper layer mounted over the read-only rootfs. This allows system configuration changes (network settings, timezone, etc.) to persist without compromising the immutability of the verified root image. The overlay can be wiped independently to restore default configuration without a full re-flash.

### 8.2 NVMe SSD (M.2 2230) — User Data

| Parameter | Value |
|-----------|-------|
| Form factor | M.2 2230 (smallest standard NVMe) |
| Interface | PCIe Gen 2 ×1 via CM5's single PCIe lane |
| Encryption | LUKS2 full-disk encryption, AES-256-XTS |
| Key storage | Derived from ATECC608B hardware + optional user passphrase |
| Filesystem | ZFS on LUKS for user data (snapshots, compression, checksumming) |

**LVM/ZFS layout inside LUKS container:**

| Volume | Mount | Purpose |
|--------|-------|---------|
| Home | `/home/user` | User home directory, persistent |
| Data | `/data` | General storage, downloads, media |
| Containers | `/var/lib/containers` | Container images and volumes (if container sandboxing is used) |
| Logs | `/var/log` | Persistent system and application logs |
| Swap | `[swap]` | Encrypted swap space |

ZFS is used for user data and backup — snapshots, send/receive for backup, built-in checksumming. It is NOT used for per-workspace snapshotting or containers.

---

## 9. Power System

### 9.1 Battery

| Parameter | Value |
|-----------|-------|
| Chemistry | Li-Po single cell (3.7V nominal, 4.2V max) |
| Capacity | 5000mAh |
| Form factor | Custom-dimension flat pouch cell to fit left zone of lower shell |
| Expected runtime | 4–8 hours depending on workload, brightness, radio usage |

### 9.2 Charging & Power Management

| Component | Purpose | Interface |
|-----------|---------|-----------|
| Charging IC | USB-PD compatible, 5V/9V fast charge | I2C to CM5 (e.g. BQ25895 or BQ25792) |
| PMIC | Rail generation (3.3V, 1.8V, 1.0V for CM5) | (e.g. TPS65219 or similar) |
| USB-PD controller | PD negotiation, informs charger of negotiated voltage | Independent of CM5 (e.g. FUSB302) |
| Fuel gauge | Coulomb counter for accurate battery percentage | I2C to CM5 (e.g. BQ27441 or MAX17048) |
| Hall effect sensor | Clamshell open/close detection via magnet in lid | GPIO to CM5 (e.g. DRV5023) — triggers suspend/wake |
| Power button | Short press = suspend, long press = hard power off | GPIO via PMIC |

---

## 10. Connectivity

### 10.1 WiFi & Bluetooth

| Radio | Source | Details |
|-------|--------|---------|
| WiFi | CM5 onboard | 802.11ac (WiFi 5), 2.4/5GHz dual-band |
| Bluetooth | CM5 onboard | 5.0 BLE + Classic |
| Antenna | External via U.FL | Recommended for handheld form factor RF performance |

Privacy: MAC address randomization via `wpa_supplicant` on every association.

### 10.2 WWAN — Cellular Modem

The WWAN modem connects via USB 3.0 from the CM5 to an M.2 B-key slot on the motherboard.

| Parameter | Detail |
|-----------|--------|
| Interface | USB 3.0 (not PCIe — PCIe lane is used by NVMe) |
| Connector | M.2 B-key on carrier board |
| Band compatibility | Must cover US and Japan LTE/5G bands |
| Candidate (5G) | Quectel RM520N-GL — 5G Sub-6 + LTE fallback. US: n25/n41/n66/n71, Japan: n3/n28/n77/n78 |
| Candidate (LTE) | Quectel EC25-AF — LTE Cat 4, lower power/cost, US+Japan bands |
| SIM | eSIM preferred (privacy — no physical card to clone). nano-SIM slot as fallback |
| AT commands | Via UART or USB CDC-ACM |
| Linux stack | ModemManager + NetworkManager |
| Antenna | 2× U.FL connectors on carrier board (main + diversity) |

**Privacy note:** IMEI is a persistent device identifier. eSIM does not solve IMEI tracking.

### 10.3 USB-C (External)

Single port. Charging + data + optional display/ethernet output. See section 5.3 for mux design.

---

## 11. Audio

| Component | Purpose | Interface |
|-----------|---------|-----------|
| Audio codec | DAC/ADC | I2S (e.g. PCM5102A or ES8388) |
| Speaker | Mono or stereo, small drivers | Class-D amp (e.g. PAM8302, MAX98357) |
| Microphone | MEMS mic for voice input | I2S (e.g. SPH0645LM4H). **Hardware kill switch on power rail.** |
| 3.5mm headphone jack | Analog audio output | Routed through codec |
| Linux audio | PipeWire | Low latency, Bluetooth audio routing, replaces PulseAudio |
| Voice input | On-device STT | Whisper.cpp on CM5 CPU. Used for command palette, URL entry, text fields |

---

## 12. NFC & RFID

These are on the **main motherboard** (not the optional daughterboard).

| Capability | Chip | Interface | Frequency |
|------------|------|-----------|-----------|
| NFC | NXP PN532 or PN7150 | I2C (PN7150 preferred) | 13.56MHz — ISO 14443A/B, ISO 15693 |
| 125kHz RFID | Separate reader module (EM4100/HID Prox compatible) | SPI or UART | 125kHz |

**NFC capabilities:** MIFARE read/write, NFC-A/B/F/V, Host Card Emulation (HCE) via libnfc/nfcpy. Tap-to-pay with real payment networks requires certified Secure Element and payment network approval — not feasible without certification. Personal NFC automation (door locks, data tags, custom tags) works fully.

**Antenna placement:** Lower screen area / bottom shell, following KTR-001 precedent for comfortable tag scanning.

**Linux stack:** `libnfc`, `nfcpy`, `neard` daemon.

---

## 13. Optional Daughterboard — RF & Biometrics

The following components are **not on the main motherboard**. They live on a small optional daughterboard that attaches via FPC or pin header. This keeps the base device simpler and allows the RF/biometric features to be added or omitted independently.

### 13.1 Sub-1GHz RF

| Parameter | Detail |
|-----------|--------|
| Chip | TI CC1101 (same as Flipper Zero) |
| Interface | SPI + 2× GPIO (GDO0, GDO2) |
| Frequencies | 300–348MHz, 387–464MHz, 779–928MHz |
| Capabilities | TX/RX ASK/OOK/FSK/GFSK/MSK. Capture and replay remote signals |
| Antenna | 50Ω SMA or U.FL |
| Linux | SPI userspace (spidev) + CC1101 userspace library |
| Legal | RX always legal. TX on 433/915MHz ISM legal at low power in US (FCC Part 15) and Japan (ARIB STD-T67) |

### 13.2 Infrared

| Parameter | Detail |
|-----------|--------|
| TX | IR LED (940nm) driven by GPIO via NPN transistor. PWM for 38kHz carrier |
| RX | TSOP38238 or equivalent 38kHz IR receiver, direct GPIO |
| Protocols | NEC, RC5, RC6, Samsung, Sony SIRC, Panasonic — software decoded |
| Linux | LIRC (Linux Infrared Remote Control) |
| GPIO usage | 1× PWM-capable GPIO for TX, 1× GPIO for RX |

### 13.3 Fingerprint Sensor

| Parameter | Detail |
|-----------|--------|
| Chip | Goodix GT9368 or similar capacitive sensor |
| Interface | USB or SPI |
| Linux | `libfprint` 1.90+ / `fprintd` daemon (D-Bus API) |
| Use cases | Boot unlock, app authentication, sudo elevation |
| Fallback | Always provide non-biometric fallback (PIN pad via gamepad input) |

---

## 14. Security Architecture

### 14.1 Threat Model

Minerva is a personal device with a serious security posture. The goal is defense-in-depth: even if one layer is compromised, other layers limit damage.

### 14.2 Secure Element — ATECC608B

| Parameter | Detail |
|-----------|--------|
| Chip | Microchip ATECC608B |
| Interface | I2C, 3.3V, ~3×3mm footprint |
| Key storage | 16 hardware slots — keys are write-only, never extractable |
| Operations | ECDH key agreement, HMAC-SHA256, hardware RNG, monotonic counter (anti-rollback) |
| LUKS integration | LUKS2 master key derived via ATECC608B HMAC — key never stored on disk |
| Two-factor | Optional: key = KDF(ATECC_HMAC(device_secret) + user_passphrase) |
| Library | Microchip `cryptoauthlib` — Linux ARM, MIT licensed |

### 14.3 Secure Boot Chain (Goal)

The intent is to establish a verified boot chain from U-Boot through the kernel to the rootfs:

1. **U-Boot** — signed bootloader in eMMC partition 1
2. **dm-verity** — kernel verifies Slot A rootfs integrity at boot via hash tree
3. **Fallback** — verification failure → automatic boot to Slot B recovery
4. **ATECC608B** — LUKS key derivation ensures NVMe user data is only accessible on this hardware

### 14.4 Optional TPM 2.0

If full TPM 2.0 is desired for measured boot, PCR attestation, or standard `tpm2-tools` compatibility:

| Parameter | Detail |
|-----------|--------|
| Chip | Infineon SLB9670 or ST33KTPM2XSPI |
| Interface | SPI1 on CM5 (SPI0 is used by Cirque trackpad) |
| Software | `tpm2-tools`, `tpm2-abrmd`, IBM TPM2 TSS |
| Added capability | Measured boot, remote attestation, key sealing to PCR state |

The ATECC608B alone is sufficient for LUKS key storage. TPM 2.0 adds attestation if needed.

### 14.5 Hardware Kill Switches

Physical slide switches that interrupt power or data lines. Software cannot override these.

| Switch | What it interrupts | Implementation |
|--------|-------------------|----------------|
| Microphone | Mic power / signal line | Slide switch on audio codec power rail or mic signal |
| Camera | Camera power rail | Switch on MIPI CSI power (future — when camera is added) |
| Radio | WiFi + BT + WWAN power | Single switch cuts all radios simultaneously |

Kill switches should be slide switches (not momentary) with physical LED indicators showing state. Placed on the side edge within thumb reach.

### 14.6 OS Security Layers

| Layer | Mechanism |
|-------|-----------|
| Immutable root | dm-verity verified rootfs on eMMC, read-only + overlayfs for config |
| Full disk encryption | LUKS2 AES-256-XTS on NVMe, key derived from ATECC608B |
| Wayland isolation | No X11 — Wayland prevents apps from reading each other's input/screen |
| MAC profiles | AppArmor or similar mandatory access control per application |
| Network namespacing | Per-app or per-container network isolation possible |
| No systemd | Alpine uses OpenRC — smaller attack surface |

### 14.7 App Sandboxing (Decision Pending)

The sandboxing model for applications is not yet finalized. Options under consideration:

1. **LXC/Podman containers** — each app or app group runs in its own container with its own network namespace. Strong isolation, higher overhead. The old spec allocated an LVM volume for container storage.
2. **Wayland-level isolation only** — Smithay compositor provides input/display isolation. Apps are native Slint binaries with AppArmor profiles but no container boundary. Lightweight, lower overhead.
3. **Capability-based** — seccomp-bpf profiles and Linux capabilities per app. Fine-grained permission control without full container overhead.
4. **Hybrid** — native Slint apps run with capability/AppArmor restrictions; untrusted or third-party apps run in containers.

---

## 15. Camera (Future)

The camera is **not in scope for the initial build** but the hardware design should accommodate it.

| Parameter | Detail |
|-----------|--------|
| Position | Rear-facing, upper shell exterior |
| Interface | MIPI CSI via CM5 camera connector, ribbon through hinge |
| Candidates | RPi Camera Module 3 (12MP, IMX708) or compact M12-lens module |
| Kill switch | Hardware camera kill switch on MIPI CSI power rail |
| Use cases | QR/barcode scanning, document scanning, photography |
| Linux stack | `libcamera` + `libcamera-apps` |

---

## 16. GPIO Budget & Bus Allocation

The CM5 has **28 usable GPIO pins**. This section tracks exact bus and pin allocation.

### 16.1 SPI Bus Allocation

| Bus | Device | Pins | Notes |
|-----|--------|------|-------|
| SPI0 | Cirque GlidePoint trackpad | CLK, MOSI, MISO, CS0 + 1 GPIO (data ready IRQ) | 5 pins. Mainline `cirque_pinnacle` driver. Up to 500Hz polling. |
| SPI1 | TPM 2.0 (optional) | CLK, MOSI, MISO, CS0 + 1 GPIO (IRQ) | 5 pins. Only if TPM is included. |

### 16.2 I2C Bus Allocation

I2C devices can share a bus (each has a unique address). The CM5 exposes multiple I2C buses.

| Bus | Devices | Notes |
|-----|---------|-------|
| I2C1 (primary) | ATECC608B, PN7150 NFC, fuel gauge (BQ27441/MAX17048), charging IC (BQ25895), lower touchscreen touch controller | Shared bus, unique addresses. 2 pins (SDA + SCL). |
| I2C (via input MCU) | TLV493D hall effect right stick | The input MCU reads the right stick and relays to CM5. Not directly on CM5 I2C. |

### 16.3 UART Allocation

| UART | Device | Notes |
|------|--------|-------|
| UART0 | Debug console | Serial debug, accessible via test pads or header |
| UART1 | WWAN AT commands (optional) | Backup to USB CDC-ACM for modem control |

### 16.4 Dedicated Interfaces (Not GPIO)

| Interface | Device | Notes |
|-----------|--------|-------|
| MIPI DSI × 2 | Upper display, lower display | Dedicated display interfaces, not GPIO |
| MIPI CSI × 1 | Camera (future) | Reserved, not GPIO |
| PCIe Gen2 ×1 | NVMe M.2 2230 SSD | Dedicated lane |
| USB 3.0 | WWAN modem (M.2 B-key) | Dedicated USB 3.0 port |
| USB 2.0 | Routed to USB-C | Data + OTG |
| I2S | Audio codec (PCM5102A/ES8388), MEMS microphone | Audio data path |

### 16.5 GPIO (Digital) Allocation

| GPIO Pin(s) | Device | Notes |
|-------------|--------|-------|
| 1 | Cirque data-ready IRQ | Active-low interrupt from trackpad |
| 1 | Hall effect sensor (DRV5023) | Clamshell open/close detection |
| 3 | Kill switch sense (mic, camera, radio) | Read switch state |
| 1 | WWAN reset | Modem reset line |
| 1 | Fan PWM | Thermal management (if active cooling used) |
| 2–4 | Input MCU communication | I2C (2 pins) or SPI (4 pins) — TBD |
| 1 | TPM IRQ (optional) | Only if TPM is included |

### 16.6 Remaining GPIO for External Header

After internal allocation: **approximately 6–12 pins** available for the external GPIO header on the bottom edge of the device. Broken out on 2.54mm pitch with 3.3V power and GND rails.

### 16.7 Daughterboard GPIO (if attached)

| GPIO Pin(s) | Device | Notes |
|-------------|--------|-------|
| 4 + 2 | CC1101 Sub-GHz | SPI (CLK, MOSI, MISO, CS) + GDO0, GDO2 |
| 1 | IR TX | PWM-capable GPIO for 38kHz carrier |
| 1 | IR RX | Digital input from TSOP38238 |
| 4–5 | Fingerprint sensor | SPI (4 pins) + 1 GPIO, or USB |

The daughterboard connects to the main board's GPIO header or via a dedicated FPC. When attached, it consumes external GPIO pins, reducing the number available for user projects.

---

## 17. Minerva OS

### 17.1 Base System

| Parameter | Detail |
|-----------|--------|
| Base distribution | Alpine Linux |
| libc | musl |
| Init system | OpenRC |
| Rust target | `aarch64-unknown-linux-musl` |
| Package manager | `apk` |
| Kernel | Mainline Linux, patched for CM5 device tree + Cirque trackpad + display panel timings |

**Why Alpine:** Minimal footprint, musl libc (small, static-linking friendly for Rust), OpenRC (simple, small attack surface, no D-Bus system bus by default), well-suited for embedded/immutable OS designs.

**Why not Devuan/Debian:** Originally considered but rejected. Alpine's musl base pairs naturally with Rust static binaries and avoids glibc's weight. The entire rootfs image can be kept very small (~200–400MB).

### 17.2 Boot Flow

```
Power on
  → U-Boot (signed, eMMC partition 1)
    → Verify Slot A dm-verity hash tree
      → Success: Mount Slot A rootfs read-only
        → Apply overlayfs (config partition)
        → Start OpenRC
          → Derive LUKS key via ATECC608B
          → Unlock NVMe
          → Mount ZFS volumes
          → Launch Torchform (compositor + DE)
      → Failure: Boot Slot B recovery
```

### 17.3 Immutability Model

The rootfs on eMMC Slot A is a **verified read-only image**:
- dm-verity provides integrity verification — any block-level tampering is detected
- A small overlay partition (ext4) provides a writable upper layer via overlayfs for `/etc` and system configuration
- Wiping the overlay partition restores factory-default configuration without re-flashing the OS
- OS updates replace the entire Slot A image atomically (A/B update pattern)

### 17.4 Workspace Model

Minerva workspaces are **named contexts** (conceptually similar to VS Code workspaces), defined by `workspace.toml` files. They are NOT frozen process snapshots or containers. A workspace defines:
- Which apps/tools are associated
- Layout preferences (split configuration, which apps on which tile)
- Environment variables and project paths
- Per-workspace settings overrides

ZFS snapshots are used for user data backup, not for per-workspace snapshotting.

### 17.5 Networking

| Stack | Tool |
|-------|------|
| WiFi/Ethernet | `wpa_supplicant` + `NetworkManager` or `iwd` |
| Cellular | `ModemManager` + `NetworkManager` |
| DNS | Privacy-focused resolver (e.g. `stubby` for DNS-over-TLS) |
| Firewall | `nftables` |
| VPN | WireGuard (kernel module) |
| Bluetooth | `bluez` |

MAC address randomization on every WiFi association for privacy.

### 17.6 Audio Stack

**PipeWire** replaces PulseAudio. Handles:
- Low-latency audio playback
- Bluetooth audio (A2DP sink/source)
- Application audio routing
- Microphone input for Whisper.cpp STT

### 17.7 Voice Input

On-device speech-to-text via **Whisper.cpp** running on the CM5's Cortex-A76 cores. Used for:
- Command palette text entry
- URL entry
- Text field input when no physical keyboard is connected
- Voice commands (future)

Not cloud-dependent. Runs locally. Audio is processed and discarded — no recording stored unless explicitly requested.

### 17.8 System Services

| Service | Purpose |
|---------|---------|
| `smithay-compositor` | Torchform's Wayland compositor (see section 18) |
| `input-daemon` | uinput virtual gamepad daemon for Cirque axis synthesis + chord detection |
| `pipewire` | Audio server |
| `NetworkManager` | Network management (WiFi, cellular, VPN) |
| `ModemManager` | WWAN modem management |
| `fprintd` | Fingerprint authentication daemon (when daughterboard attached) |
| `neard` / `nfcd` | NFC daemon |
| `lirc` | IR remote daemon (when daughterboard attached) |

---

## 18. Torchform — Desktop Environment

Torchform is the custom desktop environment for Minerva. It is built from scratch — no GNOME, KDE, or existing DE is used. Every component is designed for controller-style input on a dual-screen clamshell device.

### 18.1 Project Structure (Decision Pending)

Two options are under consideration:

**Option A — Separate project:** Torchform is its own Rust crate/repo that integrates with Minerva OS. Can be developed and tested independently. Easier to port to other platforms or test on desktop.

**Option B — Subcrate within Minerva OS:** Torchform lives inside the `Minerva OS/crates/` directory as part of the workspace. Tighter coupling with OS services, shared build system.

Both options are viable. The decision should be made based on whether Torchform will ever be used outside of Minerva.

### 18.2 Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| UI toolkit | **Slint** | Declarative, Rust-native, minimal runtime, CSS-adjacent theming. Won over Qt, GTK4, Dear ImGui, and Flutter. |
| Compositor | **Smithay** | Rust-based Wayland compositor library. Manages both displays, input routing, window lifecycle. |
| Input daemon | Custom `uinput` daemon | C or Rust. Synthesizes virtual gamepad axes from Cirque trackpad. Handles chord detection logic. |
| Theming | `tokens.slint` | Single file defining all design tokens: colors, radii, spacing, typography. Imported by every app. |

### 18.3 Why These Choices

- **Qt** — Rejected. Invasive boilerplate, opinionated widget pipeline, heavy runtime.
- **GTK4** — Rejected. Same issues as Qt for this use case, plus poor Rust bindings ergonomics.
- **Dear ImGui** — Rejected. Poor visual quality without retina-scale rendering. Immediate-mode doesn't suit a persistent UI.
- **Flutter** — Considered seriously. Rejected for Slint's more natural Rust pairing and lighter footprint.
- **Slint** — Selected. Declarative `.slint` markup, Rust-native API, minimal runtime, CSS-adjacent theming system, good for custom widget development.
- **Smithay** — Selected. Rust-based Wayland compositor framework. Full control over display management, input handling, and window lifecycle without depending on an existing compositor.

### 18.4 Design Tokens — `tokens.slint`

A single `tokens.slint` file is the universal source of truth for all visual theming. Every app and component imports it.

Contents:
- **Color palette** — background, surface, primary, secondary, accent, error, text colors
- **Typography** — font families, size scale, weight scale
- **Spacing** — margin/padding scale (e.g. 4px base unit)
- **Border radius** — corner radius scale
- **Elevation/shadow** — if applicable at the display's PPI

Changing `tokens.slint` re-themes the entire system. No app should define its own colors or font sizes outside of this file.

### 18.5 Compositor Behavior (Smithay)

| Behavior | Detail |
|----------|--------|
| Display model | Two distinct Wayland outputs: upper (primary) and lower (contextual) |
| Window management | Fullscreen-first. Optional horizontal split (2 tiles max). No floating. |
| Focus model | D-pad moves focus spatially between UI elements. L1/R1 switches tiles. |
| App switching | Start button opens app switcher overlay |
| System menu | L2+R2 chord opens global system radial menu |
| Suspend/wake | Hall effect sensor triggers suspend on lid close, wake on open |
| Security | Wayland isolation — apps cannot read each other's input or framebuffer |

### 18.6 Radial Menus

Radial menus are the primary interaction pattern — they replace traditional menus, toolbars, and context menus.

- **L2 held** → app-specific radial menu (layer 1)
- **R2 held** → app-specific radial menu (layer 2)
- **L2+R2 held** → global system radial menu (brightness, volume, WiFi toggle, Bluetooth, etc.)
- Radial menus appear on the **lower touchscreen** for thumb interaction, or can be navigated with D-pad/left pad on the upper screen
- Each radial menu has 4–8 items arranged in a circle
- Nested radials are possible (select an item to open a sub-radial)

### 18.7 Command Palette

Triggered by **Select button**. A searchable command list (like VS Code's Ctrl+Shift+P) for:
- Launching apps
- Running system commands
- Searching settings
- Quick actions

Text entry via:
1. On-screen keyboard on lower touchscreen
2. Voice input (Whisper.cpp)
3. USB keyboard (if connected)

### 18.8 Lower Screen Patterns

The lower touchscreen is contextual — its content depends on the focused app on the upper screen:

| Context | Lower screen shows |
|---------|-------------------|
| App switcher open | Thumbnail grid of running apps |
| Text editor focused | Virtual keyboard or file tree |
| Settings focused | Sub-category navigation |
| Map app focused | Controls, search, zoom |
| System radial open | Radial menu with touch targets |
| Idle / home | System status: battery, time, notifications, quick toggles |

---

## 19. Application Suite

All apps are Slint + Rust. All import `tokens.slint` for consistent theming. All are designed for the controller input grammar (no mouse/keyboard assumptions).

### 19.1 Planned Apps

| App | Purpose | Status |
|-----|---------|--------|
| Settings | System configuration — display, audio, network, Bluetooth, security, about | Design phase |
| File Manager | Browse/manage files on NVMe. ZFS snapshot management. | Design phase |
| Text Editor | Code and text editing with controller-optimized navigation | Design phase |
| Networking Manager | WiFi, cellular, VPN, Bluetooth connection management | Design phase |
| GPIO Manager | View and control exposed GPIO pins, I2C/SPI bus scanner | Design phase |
| Programming Environment | Code editing + terminal + build tools for on-device development | Design phase |
| Web Browser | Search the web with a feasible and mostly featured browser, optionally behind Tor | Design phase |
| Media Viewing | Access remote/local media library (books, music, video) and allows playback | Design phase |
| CAD | Design Projects, view models, and edit them | Design phase |

### 19.2 App Design Constraints

Every app must respect:

- **No dropdown menus** — use enumeration pickers (cycle through options with A/B or D-pad)
- **No text fields requiring keyboard** — use voice input, virtual keyboard on lower screen, or command palette
- **UI controls limited to:** sliders, checkboxes, enumeration pickers
- **Navigation via D-pad** — every interactive element must be reachable by spatial focus movement
- **Radial menus for actions** — L2/R2 layers for app-specific actions
- **Fullscreen layout** — design for 1920×1080 upper screen as the primary viewport
- **Lower screen companion** — every app should define what it shows on the lower 3.5" screen, if relevant.

---

## 20. Open Questions & Decisions Pending

### Hardware

1. **Cirque trackpad size:** TM035035 (35mm) vs TM040040 (40mm) — depends on physical fit in the left zone. 35mm is closer to KTR Circle Pad area.
2. **L2/R2 analog vs digital:** Analog preferred for gaming compatibility, but adds ADC complexity in the input MCU.
3. **125kHz RFID module:** Specific part not yet selected. Needs to be separate from PN7150 (which only does 13.56MHz).
4. **Fan vs passive cooling:** Thermal testing needed with CM5 under load in the enclosed shell.
5. **Daughterboard connector:** FPC vs pin header for optional RF/biometric board.
6. **Input MCU choice:** RP2040 vs STM32F0. RP2040 is cheaper and has USB HID; STM32F0 has better ADC for analog triggers.
7. **External GPIO pin count:** Exact count depends on final internal allocation. Target: at least 6 pins exposed.

### Software

8. **App sandboxing model:** Containers (LXC/Podman) vs Wayland-only isolation vs capability-based (seccomp-bpf) vs hybrid. See section 14.7.
9. **Torchform project structure:** Separate repo vs subcrate within Minerva OS. See section 18.1.
10. **Workspace persistence:** How are workspace.toml files managed? Per-project? Global registry?
11. **Update mechanism:** How are Slot A images built, signed, and deployed? OTA vs USB flash?
12. **Container runtime:** If containers are used, Podman (daemonless, rootless) vs LXC (system containers). Alpine packages both.
13. **Display server for lower screen:** Does the lower screen get its own Slint window, or is it managed as a distinct Wayland output with its own surface tree?
14. **Whisper.cpp model size:** Tiny/base/small — tradeoff between accuracy and CPU usage on CM5.

---

*This document is the single source of truth for the Minerva project's design intent. Component choices may change; the purpose and constraints documented here are what matter.*
