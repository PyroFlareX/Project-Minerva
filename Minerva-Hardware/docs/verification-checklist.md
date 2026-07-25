# Minerva Carrier + Face Board — Connectivity Verification Checklist

Generated 2026-07-19 from kicad-cli netlist + ERC. **Carrier ERC: 0 errors. Face board ERC: 0 errors.**
Method: every net exported via `kicad-cli sch export netlist`; every component pin classified as connected / no-connect (flagged) / single-node stub; 35 carrier + 28 face-board functional assertions executed programmatically.

## 1. System assertions (all verified pass)

### Carrier (35/35)

| # | Check | Detail |
|---|-------|--------|
| 1 | [x] `VBUS` | USB-C VBUS -> BQ25798 charger + OTG switch + PD sense |
| 2 | [x] `CC1` | CC1 -> TPS65987D (PD negotiation) |
| 3 | [x] `CC2` | CC2 -> TPS65987D |
| 4 | [x] `BATP` | battery + charger + fuel gauge |
| 5 | [x] `SYS_OUT` | BQ SYS -> boost input |
| 6 | [x] `QON` | ship-mode QON via D6 |
| 7 | [x] `TS` | TS 25C emulation divider |
| 8 | [x] `BQ_SDA` | BQ I2C SDA: charger+gauge+face MCU |
| 9 | [x] `BQ_SCL` | BQ I2C SCL |
| 10 | [x] `PD_I2C_SDA` | PD I2C -> face MCU |
| 11 | [x] `PD_I2C_SCL` | PD I2C SCL |
| 12 | [x] `PD_I2C_IRQ` | PD IRQ |
| 13 | [x] `SDA_I2C` | CM5 I2C1 <-> face MCU |
| 14 | [x] `SCL_I2C` | CM5 I2C1 SCL |
| 15 | [x] `PWR_BUT` | power button: CM5+ship diode+face MCU |
| 16 | [x] `nRPIBOOT` | rpiboot strap from face MCU |
| 17 | [x] `AMP_nMUTE` | amp mute from face MCU |
| 18 | [x] `AMP_nSD` | amp shutdown from face MCU |
| 19 | [x] `USB2_P` | USB2/rpiboot D+ |
| 20 | [x] `USB2_N` | USB2/rpiboot D- |
| 21 | [x] `+5v` | boost -> CM5, HDMI ribbon, face, pads |
| 22 | [x] `+3.3v` | single unified rail |
| 23 | [x] `DP TX via C91` | J23.A2 <-> HD3SS460 |
| 24 | [x] `DP TX via C92` | J23.A3 <-> HD3SS460 |
| 25 | [x] `DP TX via C93` | J23.B2 <-> HD3SS460 |
| 26 | [x] `DP TX via C94` | J23.B3 <-> HD3SS460 |
| 27 | [x] `USBC_RX1_P` | port <-> mux |
| 28 | [x] `USBC_RX1_N` | port <-> mux |
| 29 | [x] `USBC_RX2_P` | port <-> mux |
| 30 | [x] `USBC_RX2_N` | port <-> mux |
| 31 | [x] `USBC_SBU1` | port <-> mux |
| 32 | [x] `USBC_SBU2` | port <-> mux |
| 33 | [x] `DSI1 exclusive` | CM5 DSI1 -> SN65DSI86 only (J16 removed) |
| 34 | [x] `J1 HDMI ribbon` | HDMI0 TMDS x4 to upper display FFC |
| 35 | [x] `J5 lower display` | DSI0 lanes + clock |

### Face board (28/28)

- [x] 15 buttons `BUT_A..BUT_HOME` each reach A1 (Core2350B GP12–GP26); 11 on local switches SW2–SW12, 4 shoulder (`BUT_L/ZL/R/ZR`) on J3 flex connector
- [x] 10 MCU control signals (`PD_I2C_*`, `SDA/SCL_I2C`, `BQ_*`, `PWR_BUT`, `AMP_n*`) connect A1 ↔ J2; `nRPIBOOT` intentionally bypasses A1 and runs SW11 → J2.11
- [x] `+5V`: A1.VBUS + J2.1 + PWR_FLAG; `GND`: J2.2/14, J3.3/6, all A1 GND pins

## 2. Board-to-board interconnect contract (J25 carrier = J2 face, pin-for-pin)

| Pin | Net (carrier) | Net (face) | Function |
|---|---|---|---|
| 1 | `+5v` | `+5V` | +5 V feed to face board |
| 2 | `GND` | `GND` | GND |
| 3 | `PD_I2C_SDA` | `PD_I2C_SDA` | PD controller I2C SDA (TPS65987D) |
| 4 | `PD_I2C_SCL` | `PD_I2C_SCL` | PD I2C SCL |
| 5 | `PD_I2C_IRQ` | `PD_I2C_IRQ` | PD IRQ/event |
| 6 | `SDA_I2C` | `SDA_I2C` | CM5 I2C1 SDA (SoC link) |
| 7 | `SCL_I2C` | `SCL_I2C` | CM5 I2C1 SCL |
| 8 | `BQ_SDA` | `BQ_SDA` | BQ25798+MAX17048 I2C SDA |
| 9 | `BQ_SCL` | `BQ_SCL` | BQ I2C SCL |
| 10 | `PWR_BUT` | `PWR_BUT` | Power button (also CM5 92 + ship-mode D6) |
| 11 | `nRPIBOOT` | `nRPIBOOT` | CM5 nRPIBOOT strap (MCU-driven) |
| 12 | `AMP_nMUTE` | `AMP_nMUTE` | PAM8406 ~MUTE (open-drain) |
| 13 | `AMP_nSD` | `AMP_nSD` | PAM8406 ~SHDN (open-drain) |
| 14 | `GND` | `GND` | GND |

Footprint both sides: `Molex_PicoBlade_53047-1410_1x14` (verify mating cable orientation at layout).

## 3. Reviewed intentional stubs (single-node nets — signed off)

| Net | Pin | Rationale |
|---|---|---|
| `EEPROM_nWP` | CM5 pin 20 | float = EEPROM writable; label kept for documentation |
| `DSI86_IRQ` | U20.A3 | ti-sn65dsi86 driver runs without IRQ; spare CM5 GPIO can pick it up later |
| `TPS_GPIO0` | U22.16 | PD boot-status monitor point, optional |
| `USB3-1-D_P/N` | CM5 163/165 | port-1 USB2 pair unused — J23 D± comes from the dedicated USB2 (bootrom) interface; USB3-1 SS-only is acceptable, fallback enumerates via OTG port |
| `W_DISABLE` | J3.8 | float = modem enabled (module internal PU); tie low only for RF-kill |
| `RP_BOOTSEL/RUN/SWDIO/SWCLK/USB_N/USB_P/3V3` (face) | A1 | MCU debug/flash stubs — fit pads or header at layout |

## 4. Display / video paths (verified)

- [x] **Upper display = J1** `HDMI_D_1.4` 20-pin FFC (TE 2-1734839-0): HDMI0 TMDS×3+CLK, HPD, CEC, DDC (`HDMI0_SCL/SDA`), +5v pin 19. This is the HDMI ribbon.
- [x] **J16 removed** — it was a stale DSI-era connector renamed "HDMI RIBBON" while still carrying DSI1 in parallel with the SN65DSI86 input (electrical conflict). Its pull-up R8 removed with it. If you want the HDMI ribbon on a Hirose 22P instead of the TE 20P, rewire J1 — say so.
- [x] **Lower display = J5** 22-pin Hirose FFC: full DSI0 (4 lanes + clock), touch I2C (`SDA0/SCL0`), `CAM_GPIO0/1` (backlight/reset), +3.3v. **SPI alternative**: SPI0 remains free on the 40-pin header J8 (GPIO7–11) if the panel ends up SPI.
- [x] **DSI1 exclusive to U20 SN65DSI86** → HD3SS460 → J23 USB-C DP alt mode (TX pairs AC-coupled C91–C94, RX direct, SBU→AUX).
- [x] HDMI1 unused (all pins NC-flagged on CM5).

## 5. Power solder pads (added)

- [x] TP10/TP11 = `+5v`, TP12/TP13 = `GND` — `TestPoint_Pad_D2.0mm` on the Power and UserIO sheet, for manual power taps.

## 6. Footprint audit results

All 189 components have footprint assignments; corrections applied this pass:

| Ref | Was | Now |
|---|---|---|
| R13,R17–R20 (power) | empty | `R_0402_1005Metric` |
| C12,C13 (PCIe) | empty | `C_0402_1005Metric` |
| SW2–SW12 (face) | empty | `SW_SPST_SKQG_WithStem` |
| D6,D7 | nonexistent `D_SOT-23_ANK` | `SOT-23` |
| J22 | nonexistent Horizontal variant | `JST_SH_BM03B ... Vertical` |
| J5,J16→J5 only | broken CM5IO ref | `Connector_FFC-FPC:Hirose_FH12-22S` |
| L1,L2 | broken CM5IO/rev2 refs | `Inductor_SMD:L_Bourns_SRP5030T` |
| U21 | nonexistent EP variant | `WQFN-28-1EP_3.5x5.5mm_P0.5mm_EP2.05x4.05mm_ThermalVias` |
| U22 | nonexistent EP5.15 name | `Minerva:TPS65987D_VQFN56_RSH` from the TI RSH mechanical drawing |
| U31 | nonexistent EP0.64x1.36 name | `Minerva:MAX17048_TDFN8` from the Maxim TDFN drawing |
| M6/M7 | empty | Manual M.2 standoff/screw hardware; parked PCB documentation footprints excluded from pick-and-place |
| H2/H3 | broken CM5IO ref | `MountingHole_2.7mm_M2.5_DIN965` |

### Custom footprint blocker resolution

- [x] `Minerva:USBC_24P_QT143` (SHOU HAN TYPE-C 24P QT 143, LCSC C5156605 CAD)
- [x] `Minerva:Core2350B_stamp64` (Waveshare Core2350B0 wiki drawing, 64 stamp holes)
- [x] `Minerva:nFBGA-64_ZQE_5x5mm_P0.5mm` (SN65DSI86)
- [x] `Minerva:VQFN-20-1EP_3.5x4.5mm_P0.5mm_EP2.15x3.15mm` (TPS61088)
- [x] `Inductor_SMD:L_Coilcraft_XAL7070-XXX` for selected XAL7070-182MEC
- [x] `CM5IO.pretty` recovered from the official Raspberry Pi CM5 IO board design for the CM5 module and both M.2 sockets

## 7. Per-component connectivity (auto-verified)

Legend: conn = pins on multi-node nets, NC = no-connect flagged, stub = single-node labeled net (see §3).

### Carrier (Minerva-Carrier + child sheets)

| ✓ | Ref | Value | Footprint | conn | NC | stub |
|---|---|---|---|---|---|---|
| [x] | BT3 | ML1220 | BatteryHolder_Keystone_3000_1x12mm | 2 | 0 | 0 |
| [x] | C1 | 10 uF | C_0201_0603Metric | 2 | 0 | 0 |
| [x] | C2 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C3 | 100uF | CP_EIA-7343-31_Kemet-D | 2 | 0 | 0 |
| [x] | C4 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C5 | 4.7uF 25V | C_0201_0603Metric | 2 | 0 | 0 |
| [x] | C6 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C7 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C8 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C9 | 100n | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C10 | 100n | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C11 | 4.7nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C12 | C | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C13 | C | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C14 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C15 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C16 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C17 | 10u | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C18 | 100n | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C19 | 0.1uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C20 | 100n | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C21 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C22 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C23 | 10 uF | C_0201_0603Metric | 2 | 0 | 0 |
| [x] | C24 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C25 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C26 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C27 | 0.1uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C28 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C29 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C30 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C31 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C32 | 10uF | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C33 | 47nF, 25V X7R | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C34 | 47nF, 25V X7R | C_01005_0402Metric | 2 | 0 | 0 |
| [x] | C70 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C71 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C72 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C73 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C74 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C75 | 10uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C76 | 10uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C77 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C78 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C79 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C80 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C81 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C82 | 10uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C83 | 10uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C84 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C85 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C86 | 390pF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C87 | 390pF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C88 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C89 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C90 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C91 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C92 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C93 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C94 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C95 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C96 | 10uF | C_0603_1608Metric | 2 | 0 | 0 |
| [x] | C97 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C98 | 10uF | C_0603_1608Metric | 2 | 0 | 0 |
| [x] | C99 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C100 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C101 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C102 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C103 | 3.3nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C104 | 47nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C105 | 1uF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C106 | 100nF | C_0402_1005Metric | 2 | 0 | 0 |
| [x] | C107 | 22uF 10V | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C108 | 22uF 10V | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C109 | 22uF 10V | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | C110 | 22uF 10V | C_0805_2012Metric | 2 | 0 | 0 |
| [x] | D1 | LED Red | LED_0603_1608Metric | 2 | 0 | 0 |
| [x] | D2 | LED Green | LED_0603_1608Metric | 2 | 0 | 0 |
| [x] | D4 | LED | LED_0201_0603Metric | 2 | 0 | 0 |
| [x] | D5 | LED Green | LED_0603_1608Metric | 2 | 0 | 0 |
| [x] | D6 | BAT54 | SOT-23 | 2 | 0 | 0 |
| [x] | D7 | BAT54 | SOT-23 | 2 | 0 | 0 |
| [x] | J1 | HDMI_D_1.4 | TE_2-1734839-0_1x20-1MP_P0.5mm_Horizonta | 20 | 0 | 0 |
| [x] | J3 | Bus_M.2_Socket_B | CONN67_2199230_TEC | 29 | 37 | 1 |
| [x] | J4 | Bus_M.2_Socket_M | M.2 M Key socket 2230 | 34 | 36 | 0 |
| [x] | J5 | Conn_01x22_Female | Hirose_FH12-22S-0.5SH_1x22-1MP_P0.50mm_H | 22 | 0 | 0 |
| [x] | J6 | THD-02-R | PinHeader_2x02_P2.54mm_Vertical | 4 | 0 | 0 |
| [x] | J7 | JAE_SIM_Card_SF72S006 | JAE_SIM_Card_SF72S006 | 8 | 1 | 0 |
| [x] | J8 | THD-20-R | PinSocket_2x20_P2.54mm_Horizontal | 40 | 0 | 0 |
| [x] | J14 | JST_SHBM04B-SRSS-TB | JST_SH_BM04B-SRSS-TB_1x04-1MP_P1.00mm_Ve | 4 | 0 | 0 |
| [x] | J20 | SPK_1.25mm_4P | Molex_PicoBlade_53398-0471_1x04-1MP_P1.2 | 4 | 0 | 0 |
| [x] | J21 | SPK_1.25mm_4P | Molex_PicoBlade_53398-0471_1x04-1MP_P1.2 | 4 | 0 | 0 |
| [x] | J22 | AUX_IN_3.5mm | JST_SH_BM03B-SRSS-TB_1x03-1MP_P1.00mm_Ve | 3 | 0 | 0 |
| [x] | J23 | USB-C 24P (C5156605) | USBC_24P_QT143 | 25 | 0 | 0 |
| [x] | J24 | BATT JST-PH 2P | JST_PH_B2B-PH-K_1x02_P2.00mm_Vertical | 2 | 0 | 0 |
| [x] | J25 | FACEPLATE 14P | Molex_PicoBlade_53047-1410_1x14_P1.25mm_ | 14 | 0 | 0 |
| [x] | L1 | 2.2uH | L_Bourns_SRP5030T | 2 | 0 | 0 |
| [x] | L2 | 1uH | L_Bourns_SRP5030T | 2 | 0 | 0 |
| [x] | L3 | 1.5uH 12A | L_Coilcraft_XAL7070-152 | 2 | 0 | 0 |
| [x] | Module1 | ComputeModule5-CM5 | Raspberry-Pi-5-Compute-Module | 158 | 39 | 3 |
| [x] | R1 | 1k | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R2 | 10k | R_0201_0603Metric | 2 | 0 | 0 |
| [x] | R3 | 1k | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R4 | nf | R_0805_2012Metric_Pad1.20x1.40mm_HandSol | 2 | 0 | 0 |
| [x] | R5 | 0R | R_0805_2012Metric_Pad1.20x1.40mm_HandSol | 2 | 0 | 0 |
| [x] | R6 | 2.2K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R7 | 2.2K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R9 | 2.2K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R10 | 1k | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R11 | 10K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R12 | 15K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R13 | 100Ω | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R14 | 100K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R15 | 10K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R16 | 2.2K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R17 | 3kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R18 | 30.1kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R19 | 10kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R20 | 10kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R50 | 51K 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R51 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R52 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R53 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R54 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R55 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R56 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R57 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R58 | 1M | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R59 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R60 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R61 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R62 | 10K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R63 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R64 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R65 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R66 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R71 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R72 | 100K | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R73 | 0R (DNP option) | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R74 | 0R (DNP option) | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R75 | 1kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R76 | 5.23kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R77 | 10kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R78 | 182kΩ 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R79 | 56kΩ 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R80 | 8.2kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R81 | 64.9kΩ 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R82 | 100kΩ 1% | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R84 | 100kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R85 | 2.2kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | R86 | 2.2kΩ | R_0402_1005Metric | 2 | 0 | 0 |
| [x] | SW1 | Right angle Tact button | SW_Tactile_SPST_Angled_PTS645Vx58-2LFS | 2 | 0 | 0 |
| [x] | TP3 | TestPoint | TestPoint_Pad_2.0x2.0mm | 1 | 0 | 0 |
| [x] | TP5 | TestPoint | TestPoint_Pad_2.0x2.0mm | 1 | 0 | 0 |
| [x] | TP10 | +5v PAD | TestPoint_Pad_D2.0mm | 1 | 0 | 0 |
| [x] | TP11 | +5v PAD | TestPoint_Pad_D2.0mm | 1 | 0 | 0 |
| [x] | TP12 | GND PAD | TestPoint_Pad_D2.0mm | 1 | 0 | 0 |
| [x] | TP13 | GND PAD | TestPoint_Pad_D2.0mm | 1 | 0 | 0 |
| [x] | U1 | BQ25798 | Texas_RQM0029A_VQFN-29_4x4mm_P0.4mm | 25 | 4 | 0 |
| [x] | U2 | ASEK-32.768KHZ-L-R-T | Crystal_SMD_3225-4Pin_3.2x2.5mm | 4 | 0 | 0 |
| [x] | U6 | AP22653W6 | SOT-23-6 | 5 | 1 | 0 |
| [x] | U8 | AP3441SHE-7B | DFN-8-1EP_2x2mm_P0.5mm_EP1.05x1.75mm | 7 | 2 | 0 |
| [x] | U20 | SN65DSI86ZQER | nFBGA-64_ZQE_5x5mm_P0.5mm | 49 | 14 | 1 |
| [x] | U21 | HD3SS460RHRT | WQFN-28-1EP_3.5x5.5mm_P0.5mm_EP2.05x4.05 | 25 | 4 | 0 |
| [x] | U22 | TPS65987DDJRSHR | QFN-56-1EP_7x7mm_P0.4mm_EP5.6x5.6mm_Ther | 42 | 16 | 1 |
| [x] | U23 | W25Q32JVSS | SOIC-8_5.3x5.3mm_P1.27mm | 8 | 0 | 0 |
| [x] | U24 | AP2112K-1.8 | SOT-23-5 | 4 | 1 | 0 |
| [x] | U25 | AP2112K-1.2 | SOT-23-5 | 4 | 1 | 0 |
| [x] | U29 | PAM8406DR | SOIC-16_3.9x9.9mm_P1.27mm | 16 | 0 | 0 |
| [x] | U30 | TPS61088RHLR | VQFN-20-1EP_3.5x4.5mm_P0.5mm_EP2.15x3.15 | 20 | 1 | 0 |
| [x] | U31 | MAX17048G+T10 | TDFN-8-1EP_2x2mm_P0.5mm_EP0.8x1.2mm | 8 | 1 | 0 |

### Face board

| ✓ | Ref | Value | Footprint | conn | NC | stub |
|---|---|---|---|---|---|---|
| [x] | A1 | Core2350B0 | Core2350B_stamp64 | 33 | 24 | 7 |
| [x] | J2 | CARRIER 14P | Molex_PicoBlade_53047-1410_1x14_P1.25mm_ | 14 | 0 | 0 |
| [x] | J3 | SHOULDER 6P | Molex_PicoBlade_53047-0610_1x06_P1.25mm_ | 6 | 0 | 0 |
| [x] | SW2 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW3 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW4 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW5 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW6 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW7 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW8 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW9 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW10 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW11 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |
| [x] | SW12 | SW_Push | SW_SPST_SKQG_WithStem | 2 | 0 | 0 |

## 8. Process warning

Three schematic-state losses occurred when the KiCad GUI saved stale buffers over scripted edits (22:53 / 23:02 / 23:23). **Close KiCad or reload the project from disk before/after any scripted editing session.**

## 9. PCB status (reviewed snapshot)

- **Schematic↔PCB parity: 0 issues.** The carrier remains a routing work-in-progress: 499 unconnected items and 53 differential-routing violations (38 pair-gap warnings, 12 uncoupled-length errors, and 3 skew errors). There are no placement overlaps or cross-net shorts in this snapshot.
- The carrier contains 190 footprints. The six locked anchors remain untouched: Module1, J4, J3, J5, J14, and SW1.
- Floorplan: J23 USB-C is now at the top-left edge; its VBUS protection, U6 source switch, and U1/L2 charger cluster occupy the freed upper-left area. J8 is removed. J1 HDMI FFC remains top-right; boost U30/L3/caps remain center-left; audio U29 plus J20/J21 speakers and J24 battery remain on the left edge; the U20/U21/U22/U23/U24/U25 high-speed chain remains on the bottom side under the CM5; BT3 and test pads remain bottom-side.
- Rule areas: the existing `Wireless` keepout is honored; `M2_2230_card_envelope` reserves the NVMe card volume. Verify J14 height against the card-standoff volume during enclosure review.
- Libraries: `CM5IO.pretty` recovered from board-embedded footprints (7 parts incl. CM5 module + M.2 sockets); `Minerva.pretty` created with JLC-CAD-sourced footprints (USBC_24P_QT143 from LCSC C5156605 CAD, SN65DSI86 BGA-64, TPS61088 VQFN-20, TPS65987D VQFN-56 RSH, MAX17048 TDFN-8, BAT54 SOT-23 with corrected A/K pad map) plus project-local STEP models.
- **BAT54 polarity fix**: 2-pin diode symbol vs SOT-23 (A=1, K=3) — custom `D_SOT-23_BAT54_AK` footprint maps symbol K→pin 3. D6/D7 would have been assembled dead otherwise.
- **L3 changed to XAL7070-182ME (1.8 µH)** — no 1.5 µH variant exists in the XAL7070 family; 1.8 µH is inside TPS61088's 1–2.2 µH window, Isat 25 A.
- **J6 and J8 removed.** ID_SC/ID_SD remain intentional single-node CM5 EEPROM-ID stubs; DSI86 I2C remains probeable at R6/R7.
- USB-C shield/lugs tie to GND; J1 pad 20+MP ties to GND; M.2 B mount posts tie to GND; J23 locating pegs are NPTH.
- Board constraints target the selected six-layer HDI process: 0.20 mm minimum through drill, 0.10 mm microvia drill, and 0.075 mm minimum annular width. `Minerva-Carrier.kicad_dru` covers J23's manufacturer-defined shell geometry and its edge-mounted shield lugs.
- M6 solder nut mounts at J4's M1 pad position (2230 standoff); M6/M7 footprints remain parked as manual mounting hardware.
