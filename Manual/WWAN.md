# WWAN Connectivity — Minerva Manual

## Hardware

The Sierra Wireless EM7565 sits in Minerva's M.2 B-key slot. Despite the M.2 form
factor, it communicates over USB 2.0 — the PCIe/USB 3.0 lanes are unused. The modem
requires a nano SIM card connected via the M.2 B-key SIM pins (SIM_CLK, SIM_DATA,
SIM_RST, SIM_VCC, SIM_GND) to an external push-push nano SIM holder on the enclosure
edge.

**Supported carriers:** T-Mobile, AT&T (US); NTT Docomo, SoftBank, KDDI (Japan);
and most global 4G carriers across 26 LTE bands.

---

## SIM Cards

**Primary (US):** T-Mobile prepaid "Connected Device" data-only SIM.
- Buy at any T-Mobile store or Walmart (~$5 for the SIM)
- Activate at t-mobile.com using the tablet/hotspot flow
- Plan: $25/mo unlimited or $15/mo 5GB
- APN: `fast.t-mobile.com`

**Japan travel:** IIJmio Travel SIM (Docomo network).
- Available at airport kiosks (Narita/Haneda), Bic Camera, Yodobashi Camera,
  or any 7-Eleven / FamilyMart / Lawson convenience store
- 3–15GB plans, valid 7–30 days
- APN: `iijmio.jp`
- Coverage is blanket in Tokyo; reliable throughout Japan

---

## First-time Setup

Run once after the modem is installed:

```sh
sudo minerva-wwan setup       # Install deps, start ModemManager
sudo minerva-wwan init-ecm    # Switch modem to ECM mode (persists across reboots)
sudo minerva-wwan up          # Connect with default profile (T-Mobile)
```

ECM mode exposes the modem as a standard `usb0` Ethernet interface.
NetworkManager handles it automatically from that point on.

---

## Daily Use

```sh
minerva-wwan status           # Connection state + IP
minerva-wwan up               # Connect (T-Mobile default)
minerva-wwan down             # Disconnect
minerva-wwan test             # Ping + DNS + HTTP check
minerva-wwan watch            # Live signal monitor
minerva-wwan usage            # Session data usage (RX/TX)
```

---

## Switching to Japan SIM

1. Power down Minerva (or just stop the connection)
2. Eject the US SIM, insert the IIJmio SIM
3. Run:

```sh
sudo minerva-wwan switch iijmio
```

The script will confirm the SIM is inserted, tear down the US connection,
and bring up the Japan profile automatically.

To switch back when you land in the US:

```sh
sudo minerva-wwan switch tmobile
```

---

## Signal & Diagnostics

```sh
minerva-wwan signal           # Signal strength + band info
minerva-wwan watch            # Live monitor (refreshes every 3s)
minerva-wwan info             # Full modem hardware details
minerva-wwan logs             # ModemManager log tail
minerva-wwan at 'AT+CSQ'      # Raw AT command passthrough
```

---

## Adding Custom Profiles

```sh
minerva-wwan profile-add      # Interactive prompt: name / APN / description
minerva-wwan profiles         # List all known profiles
```

User profiles are stored at `~/.config/minerva-wwan/profiles.conf` and loaded
automatically on every invocation.

---

## Installation

```sh
sudo cp minerva-wwan.sh /usr/local/bin/minerva-wwan
sudo chmod +x /usr/local/bin/minerva-wwan
```

For auto-connect on boot, NetworkManager will bring up the last active `minerva-*`
connection automatically after `init-ecm` has been run once. No additional
configuration needed.

---

## Carrier APN Reference

| Profile    | APN                   | Carrier              |
|------------|-----------------------|----------------------|
| `tmobile`  | `fast.t-mobile.com`   | T-Mobile US          |
| `att`      | `broadband`           | AT&T US              |
| `iijmio`   | `iijmio.jp`           | IIJmio Japan (Docomo)|
| `docomo`   | `spmode.ne.jp`        | NTT Docomo direct    |
