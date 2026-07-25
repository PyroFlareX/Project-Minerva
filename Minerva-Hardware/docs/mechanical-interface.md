# Minerva PCB Mechanical Interface

All coordinates are in millimetres. Each board uses the north-west corner of `Edge.Cuts` as `(0, 0)`, with +X right and +Y down in KiCad top view. Bottom-side rotations are reported in KiCad top-view coordinates and must be mirrored by enclosure CAD.

## Carrier board

- PCB outline: **83.55 × 90.05 × 1.60 mm**.
- KiCad absolute outline origin: `(78.975, 69.975)`.
- JLCPCB `JLC06161H-3313` six-layer ENIG stack, nominal **1.60 mm**: 35 µm outer copper, 15.2 µm inner copper, and 0.0994 / 0.550 / 0.1088 / 0.550 / 0.0994 mm dielectrics. Layer order is L1 signals, L2 continuous GND, L3 continuous GND, L4 high-speed signals, L5 +5 V plane, L6 signals. L1 controlled pairs use 0.25 mm spacing with 0.128 mm (100 Ω), 0.161 mm (90 Ω), or 0.183 mm (85 Ω) traces. L4 DSI uses 0.128 mm / 0.25 mm against L3 GND. The fabrication order must request controlled impedance so JLCPCB can apply final etch compensation.
- Dedicated enclosure mounting holes: H2 `(3.525, 86.525)` and H3 `(79.525, 4.225)`, 2.7 mm finished holes for M2.5 flat-head hardware.
- Assembly fiducials: F.Cu `(4.025, 35.025)`, `(47.025, 28.525)`, `(12.025, 80.025)`; B.Cu `(6.025, 36.025)`, `(68.025, 4.025)`, `(66.025, 86.025)`. Copper target 1.0 mm, mask opening 2.0 mm.

### Carrier connectors and controls

| Ref | Function | Side | Centre X | Centre Y | Rotation | Enclosure interface |
|---|---|---:|---:|---:|---:|---|
| J1 | HDMI display FFC | F.Cu | 66.970 | 2.860 | 0° | Cable exits north |
| J5 | 22-pin display FFC | F.Cu | 14.475 | 34.225 | −90° | Side-entry FFC |
| J14 | JST-SH 4-pin | F.Cu | 74.825 | 45.025 | 180° | Vertical mating access |
| J20 | Left speaker | F.Cu | 3.450 | 56.552 | 90° | Cable exits west |
| J21 | Right speaker | F.Cu | 3.450 | 69.402 | 90° | Cable exits west |
| J22 | Display audio input | B.Cu | 29.650 | 26.050 | 180° | Bottom-side mating access |
| J23 | USB-C dock/charge | F.Cu | 8.025 | 5.315 | 180° | Receptacle shell reaches the north edge; centreline is the enclosure port datum |
| J24 | 2-pin battery | F.Cu | 3.450 | 80.722 | 90° | Cable exits west |
| J25 | Face-board 14-pin | B.Cu | 55.025 | 5.525 | 180° | Pin 1 at carrier `(55.025, 5.525)`; non-reversing harness to face-board J2 pin 1 |
| J3 | M.2 B-key WWAN | B.Cu | 52.025 | 68.775 | 180° | Reserve card and antenna-cable volume below board |
| J4 | M.2 M-key 2230 NVMe | F.Cu | 41.750 | 36.175 | 90° | Keep the defined 2230 card envelope clear |
| J7 | SIM holder | B.Cu | 12.870 | 70.310 | 180° | Provide bottom/side service access |
| SW1 | Power tact switch | F.Cu | 14.300 | 88.513 | 180° | Actuator intentionally projects 4.36 mm beyond the south board edge |

SW1 uses the stocked Kinghelm **KH-6X6X6H-ZJ**. Its vendor drawing matches the assigned PTS645 footprint: 4.5 mm signal-pin pitch, 7.0 mm anchor pitch, and 2.5 mm signal-to-anchor row spacing. The 6 mm actuator projects 4.36 mm beyond the south edge in its installed orientation.

The CM5 courtyard drawing spans `(28.465, 49.665)` to `(83.585, 89.785)`; its east line is 0.035 mm beyond the nominal `Edge.Cuts` maximum because of drawing stroke width, so enclosure CAD must treat the CM5 edge as flush rather than relying on that nominal margin. Reserve at least **87.6 × 94.1 mm** for the rotated carrier plus 2 mm wall/assembly clearance. This is larger than the current 82 mm lower-shell depth target; enclosure CAD must either provide a local carrier pocket or revise the shell depth before tooling.

## Face/controller board

- PCB outline: **138.05 × 76.05 × 1.60 mm**.
- Two-layer ENIG stack: 35 µm copper / 1.51 mm FR-4 core / 35 µm copper, black mask, white legend.
- KiCad absolute outline origin: `(19.975, 19.975)`.
- Designed for the 142 × 80.6 mm shell with approximately 2 mm nominal perimeter allowance.
- Four M2.5 holes: H1 `(4.025, 4.025)`, H2 `(134.025, 4.025)`, H3 `(4.025, 72.025)`, H4 `(134.025, 72.025)`; 2.7 mm finished diameter.
- Lower-display active-area datum: rectangle `(33.525, 6.025)` to `(104.525, 60.025)`, **71 × 54 mm**. This is currently a `User.Drawings` datum, not a routed PCB cutout: copper and the A1 module still occupy the display region. The face-board arrangement must reserve the complete selected 3.5-inch display module envelope (active area, bezel, flex, and mounting tabs) before fabrication.
- Core2350B A1: selected **Waveshare Core2350B0** (0 MB PSRAM, 16 MB flash), B.Cu centre `(69.025, 32.025)`, **25.4 × 25.4 mm (1.00 × 1.00 inch)** module envelope, representative maximum assembled height 2.8 mm from the PCB surface. Its current centre placement overlaps the display datum and is a known floorplan item, not a size error.
- Carrier interconnect J2: B.Cu centre `(90.025, 66.025)`, 90°, Molex PicoBlade 14-pin, 1.25 mm pitch. Pin 1 maps to carrier J25 pin 1.
- Shoulder interconnect J3: B.Cu centre `(69.025, 3.025)`, 180°, Molex PicoBlade 6-pin, 1.25 mm pitch.
- Assembly fiducials: F.Cu `(30.025, 3.025)`, `(108.025, 3.025)`, `(30.025, 72.025)`; B.Cu `(25.025, 5.025)`, `(113.025, 5.025)`, `(113.025, 72.025)`.

### Control centres

| Control | Ref | X | Y |
|---|---|---:|---:|
| A | SW2 | 130.031 | 38.025 |
| B | SW3 | 119.778 | 48.278 |
| X | SW4 | 119.778 | 27.772 |
| Y | SW5 | 109.525 | 38.025 |
| D-pad Up | SW6 | 17.025 | 28.025 |
| D-pad Left | SW7 | 7.025 | 38.025 |
| D-pad Right | SW8 | 27.025 | 38.025 |
| D-pad Down | SW9 | 17.025 | 48.025 |
| Start | SW10 | 71.025 | 67.025 |
| Select / nRPIBOOT | SW11 | 49.025 | 67.025 |
| Home | SW12 | 60.025 | 67.025 |

ABXY uses an exact **14.50 mm adjacent-centre pitch**. Use **8 mm maximum cap diameter**: the Y cap then has 1.0 mm clearance to the nominal display active-area edge and the A cap has 4.0 mm clearance to the PCB edge. The earlier 14 mm cap proposal cannot coexist with a 71 mm-wide display inside the 142 mm shell and was removed from the design reference.

All eleven controls use ALPS Alpine **SKQGAFE010** with KiCad footprint `Button_Switch_SMD:SW_SPST_SKQG_WithStem`. The switch stem centre is the control datum; enclosure button plungers must load the stem axially and must not bottom out on the switch body.

## Inter-board orientation

J25 and J2 are both numbered pin 1 through pin 14 and use the same 1.25 mm PicoBlade family. The harness must be a non-reversing, pin-1-to-pin-1 cable. Electrical order is: +5V, GND, PD SDA, PD SCL, PD IRQ, system SDA, system SCL, BQ SDA, BQ SCL, PWR_BUT, nRPIBOOT, AMP nMUTE, AMP nSD, GND.

The two M.2 card retention centres are carrier coordinates `(70.000, 36.175)` for J4 M-key 2230 pad `M1` and `(21.000, 65.000)` for the J3 B-key 3052 `M6` land pattern. Both use **PEM ReelFast SMTSO-M2-4ET** M2 × 0.4, 4 mm surface-mount standoffs on 6.2 mm minimum copper/mask openings. BOM items M6 and M7 each carry quantity 2; M7 specifies A2 stainless M2 × 3 mm Phillips pan-head screws to DIN 7985H / ISO 7045. The screws are manual hardware and excluded from pick-and-place; the two soldered standoffs remain in the carrier placement file.

## CAD and fabrication outputs

- `fabrication/carrier/Minerva-Carrier.step` — carrier assembly STEP.
- `fabrication/face/Minerva-Face.step` — face-board assembly STEP, including Core2350B and PicoBlade mechanical envelopes.
- `fabrication/*/gerbers/` — production copper, mask, paste, silkscreen, outline, and drill files.
- `fabrication/*/*-positions.csv` — assembly placement data.
- `fabrication/*/*-BOM.csv` — schematic-derived bill of materials.
- `fabrication/*/*-DRC.json` — machine-readable final DRC evidence.
