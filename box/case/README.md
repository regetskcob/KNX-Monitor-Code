# KNX Box case for Raspberry Pi with kBerry

A sturdy, screwed case for a Raspberry Pi 3B, 3B+, 4B or 5 with a Weinzierl KNX BAOS 838 kBerry mounted on top. It is built for use on job sites: solid walls, recessed connectors, smooth outer surfaces. The KNX terminal protrudes from the slim lid and can be unplugged with the case closed.

Modelled in [SolidCraft](https://github.com/tangency-labs/solidcraft), printed with FDM. There is only this one variant.

**Status: preview.** The insert holes are calibrated with a printed step test; the complete case with Pi and kBerry and the DIN-rail base are not fully verified yet. Of the latch clips, variant 1 (`clip-1`) won the print test; it is still being refined. Every box release contains this folder as `knx-box-case-<version>.zip`: the STLs and this description. The SolidCraft model and the exploded-view drawings are kept with the CAD source and are not part of this repository.

## Files

| File | Content |
|---|---|
| `knx-box-case-base.stl` | Base |
| `knx-box-case-base-din-rail.stl` | Base with DIN-rail (TS35) mount, alternative to the normal base |
| `knx-box-case-din-rail-clip-1.stl` … `-3.stl` | Latch clip for it, screwed to the underside of the DIN-rail base. Recommended: `-1` (one dot); `-2` and `-3` are softer test variants |
| `knx-box-case-cover.stl` | Lid |
| `knx-box-case-bridge.stl` | Module bridge, supports the kBerry from below |
| `knx-box-case-usb-cover.stl` | USB cover, optional |
| `knx-box-case-fit-test.stl` | Fit test for lid and module |
| `knx-box-case-insert-step-test.stl` | Step test for the heat-set inserts |

All STLs are in print orientation and need no supports.

**Fits** Pi 3B, 3B+, 4B and 5. The 40-pin header and the mounting holes are in the same place on all of them, so the kBerry sits identically. The Pi 2B has the same form factor as the Pi 3B; this is not verified. **Does not fit:** Pi Zero, Pi 1 A/B, Compute Modules, Pi 400/500.

## Dimensions

| | |
|---|---|
| Outside (assembled) | 100 × 69 × 29.5 mm (L × W × H); the KNX terminal protrudes about 2.4 mm |
| Base | 100 × 69 × 7 mm (rim 6 mm, bosses up to 7 mm) |
| Lid | 100 × 69 × 23.5 mm, inner ceiling at 27.0 mm, 2.5 mm thick |
| Parting line base/lid | 6 mm above the bottom edge |
| Corners (vertical) | R 4.5 mm |
| Wall thickness | 6 mm (left, front, back), 8 mm (right, LAN/USB side) |
| Interior | 86 × 57 mm, 0.5 mm clearance around the board |
| Pi board | underside 7 mm, top 8.5 mm above the case bottom |
| kBerry board | 19.9–21.5 mm above the case bottom |

Orientation: **front** = power/HDMI, **right** = LAN/USB, **left** = microSD, **back** = GPIO. Coordinates: origin at the front left corner of the Pi board, x to the right, y to the back, z from the case bottom. For outer case coordinates add 6.5 mm to x and y.

## Openings

| Opening | Position | Range | For |
|---|---|---|---|
| Front window | front wall | x 4.5–59, z 5.9–15.5, 1.5 mm outer chamfer | Micro-USB/USB-C, HDMI or 2× micro-HDMI, audio. The top edge is flush with the underside of the module bridge; the chamfer gives thick plugs room |
| Right window | right wall | y 1.5–54.5, z 5.9–25 | LAN and 2× dual USB, in both layouts |
| Left window | left wall (lid) | y 18–38, z 5.9–12.5 | microSD, aligned with the SD finger recess in the base. The Pi 5 power button and PCIe connector are behind it, covered |
| SD finger recess | left wall (base) | y 18–38, z 3.5–6 | to grip the microSD |
| Terminal opening with wire channel | top of lid, through the wall to the left | x −0.5–18.5, y 12.6–26.6, from z 21.9 | KNX terminal, bus cable to the left |
| Pin hole Ø 2.5 | top of lid | x 13.9, y 7.1 | programming button |
| Rear ventilation | back wall | 15 slots, 2 mm wide, z 13.5–24.5 | |
| Front ventilation | front wall above the window | 8 slots 2 × 4 mm, z 20.5–24.5 | |

- The sockets sit 4–6 mm behind the outer wall. Plugs with thick strain relief still go in all the way.
- The microSD card sits about 4 mm deep. You grip it with a fingernail or tweezers. This is intentional, so it is not pulled out by accident.
- The Pi 5 power button and PCIe connector are not accessible with the case closed.

## Lid in detail

Measured position of the kBerry (Pi 4B, ±0.5 mm): board x 5.5–41, y 0–56. Silkscreen of the KNX terminal x 6.4–17.9, y 13.3–25.9. Highest points above the case bottom: terminal 31.9 mm, large electrolytic capacitor 27.9 mm.

| Element | Position | Purpose |
|---|---|---|
| Terminal opening | x −0.5–18.5, y 12.6–26.6, 0.6–0.7 mm gap to the terminal | Pull terminal and cable straight up without removing the lid. The cable leaves straight through the left wall |
| Skirt | around opening and wire channel, from the ceiling to 0.5 mm above the kBerry board | keeps dust out of the interior and supports the module from above when the terminal is pulled |
| Skirt walls | front 1.2 mm, back 2.0 mm (to y 28.6), right 1.7 mm (to x 20.2); fully open up to z 24.8 at the SMD part in front of the terminal (x 18.3–20.3, y 8–16), the wall starts above it | as thick as the neighbouring components allow |
| Ribs on the skirt | back and right outside, 1.5 × 1.7 mm | connect skirt and ceiling, against sideways pull on the cable. On the left the skirt hangs on the case wall |
| Chamfers | channel floor inside and outside 1.5 mm each, top edges of the opening 1 mm | no sharp edge on the cable |
| Channel floor | z 21.9 all the way from the outer wall to the terminal, without a web, level with the skirt's lower edge and below the lowest entry of the terminal (about z 24.4) | nothing in the way even with two cables (looped through) and all four entries per pole |
| Pockets in the ceiling | above both capacitors (Ø 8 / Ø 7) and the programming button (x 10.2–17.6, y 3.4–10.3), each up to z 28.7 | 0.8 mm clearance above the large capacitor, 0.8 mm skin above it |
| Guides | left x 3.0–5.2 (y 30.5–56.5), right x 41.3–43.3 (y 6.5–56.5), lower edge z 20 | lateral hold, 0.3 mm play to the module edge. Open at the front: in the first build the front left guide, the front end of the right guide and both hold-downs above the bridge collided; they were removed |

The guides press on no component of the Pi. Display and camera connectors, GPIO pins and SoC are lower or beside them.

## Module bridge `knx-box-case-bridge.stl`

The kBerry has no mounting holes of its own and hangs only on the header at the back. The bridge supports the front end of the module from below, so plugging in the terminal puts no force on the GPIO pins.

| Element | Position | Purpose |
|---|---|---|
| Posts | above the front Pi holes (3.5 / 3.5 Ø 6 and 61.5 / 3.5 Ø 5.5) | stand on the Pi board above the bosses in the base. The right one is narrower because of the Pi 5 PoE pins |
| Beam | x 3.5–61.5, y 0.5–6.5, z 15.5–19.7 | carries the front edge of the module, 0.2 mm clearance. It spans USB-C, HDMI and audio |
| Finger | x 7.5–12.5, y 6.5–14, top z 19.7 | support directly in front of the terminal |
| Holes | Ø 2.8 with counterbore Ø 5 × 2 mm | screw heads recessed |

Load path when plugging in: terminal → module → bridge → posts → Pi board above the bosses. When unplugging: terminal → module → skirt → lid. The rubber dot under the module can be removed. Size 64 × 13.5 × 11.2 mm.

## USB cover `knx-box-case-usb-cover.stl`

Optional cap for unused USB sockets. It closes the right window except for the RJ45 socket.

- **Position:** the plate fills the window in front of the USB sockets (x 88.2–93.5, y 1.7–36.5, z 6.1–24.8), flush with the outer wall, 0.2 mm clearance.
- **Hold:** four rounded pegs (11 × 1.8 mm) reach about 6 mm into the sockets, in their lower half. Good hold from about 4 mm.
- **Finger recess:** at the edge towards the RJ45 socket, 2.4 mm deep. To remove, pull out at an angle there; the cap tilts around its front edge.
- **Pi 4B:** recess towards the RJ45 socket. **Pi 3B/3B+ and 5:** insert the same cap rotated by 180° (upside down). It is symmetrical, so the recess is again at the RJ45 socket.
- Not yet tested on a Pi. Open: whether the contact tongue in the sockets is really at the top.

## DIN-rail base `knx-box-case-base-din-rail.stl` and clip `knx-box-case-din-rail-clip-1…3.stl`

Alternative to the normal base when the box should sit on a TS35 DIN rail (EN 60715, 35 × 7.5 mm) in a distribution board. Lid, inserts, module bridge and assembly stay the same.

- **Orientation:** the short side (69 mm ≈ 4 modules) runs along the rail. The KNX cable points up, LAN and USB down. Power (USB-C) and HDMI are at the side; use an angled plug there or leave some space to the neighbouring device.
- **Height:** the base is 3 mm thicker than the normal one, so the box is 32.5 mm high. Including the rail it rises about 40 mm above the mounting plane.
- **Rail groove in the base:** 35.4 mm wide, across the whole base. At the top (KNX side) a fixed lip holds with 1.8 mm overlap.
- **Latch clip as a separate part:** 3 mm high, at the bottom (LAN side) in a pocket of the base.
  - Why a latch: the first clip had a spring beam screwed at both ends with a catch along almost its whole length. At the ends the catch could not deflect, and in the middle PLA would have been overstretched when snapping in.
  - Design: two screwed anchors, each with a bar to the back. Between them a stiff latch (36 mm catch, 1 mm lead-in chamfer) hangs on two meander springs, one above and one below the tab. The latch moves as a whole, parallel, and releases the rail along its full length. The anchors guide it sideways with 0.4 mm play.
  - Variants, all with the same screw points, recognisable by the dots on the anchor:

    | File | Dots | Springs | Force at 2.2 mm (PLA estimate) | Bending stress at the stop |
    |---|---|---|---|---|
    | `knx-box-case-din-rail-clip-1.stl` | 1 | 2 × 4 webs, 1.2 mm | approx. 5 N | approx. 45 MPa |
    | `knx-box-case-din-rail-clip-2.stl` | 2 | 2 × 4 webs, 1.0 mm | approx. 3 N | approx. 38 MPa |
    | `knx-box-case-din-rail-clip-3.stl` | 3 | 2 × 5 webs, 0.8 mm | approx. 1.3 N | approx. 25 MPa |

    The values are rough beam calculations. Variant 1 is close to the limit for PLA; with PETG force and stress drop by about 40 %.

    **Recommended: variant 1 (`clip-1`).** It won the print test against the softer variants. It is still being refined; `clip-2` and `clip-3` stay as test variants for now.
  - Spring travel: the rail needs about 2 mm. The tab hits the end of its channel in the base after 2.6 mm, which protects the springs from overstretching. Even then about 0.9 mm clearance remains between the webs.
  - Fastening: two M3 heat-set inserts (Ø 4.5) in bosses in the base, at x 66.5 / y 8.5 and y 55 (clear of the M2.5 holes of the Pi bosses), and two M3 × 6 screws with flat or button head (ISO 7380, head ≤ 6 × 1.8 mm) from below. Springs and latch have 1 mm clearance to the pocket floor.
- **Mounting:** hook the box onto the rail at the top, press at the bottom until the spring snaps in.
- **Removing:** put a screwdriver into the hole of the release tongue at the bottom (near the LAN side) and pull outwards. The spring gives way and the box tilts off the rail at the top.
- **Lid screws:** the counterbores go through the additional layer. M3 × 8 still fits.
- **Printing:** both parts without supports.
  - Base: underside on the bed. The groove is a 35 mm bridge, the clip pocket a 21 mm bridge.
  - Clip: flat, the side with the counterbores and dots on the bed. Springs, latch, lip and tongue all stand on the bed, so the springs bend within the layer plane. At least 2 wall lines, 100 % infill.
  - Do not force supports in the slicer, otherwise they stick in the clip pocket.
- **Inserts in the base:** the two M3 inserts for the clip go in from below, with the base lying upside down.
- **Mounting the clip:** lay the base upside down and melt the two M3 inserts into the bosses of the clip pocket. Put the clip into the pocket with the counterbores facing out, the catch lip towards the rail groove, the tongue to the side. Tighten two M3 × 6 ISO 7380. Then assemble the base as usual.
- **Verified:** in the model against a TS35 profile. In its end position the rail is free at both the base and the clip. Counter-check: lifted by 0.35 mm, it touches both lips. The insert bosses do not touch the Pi (1 mm clearance to the board). The three clips sit in the pocket without collision; counter-check: 0.3 mm higher, they collide. On the print: variant 1 (`clip-1`) is chosen but still needs refinement.

## Heat-set inserts

CNC Kitchen, M2.5 × 4 in the four bosses of the base and M3 × 4 in the four corner columns of the lid.

| Insert | Hole in the model | Depth |
|---|---|---|
| M2.5 × 4 | Ø 3.4 | 5.5 mm, boss Ø 7.5 with Ø 6 collar |
| M3 × 4 | Ø 4.5 | 8 mm, column Ø 7.2 |

The dimensions come from the step test and apply to **0.2 mm layer height**. At 0.28 mm the printed holes came out noticeably tighter (Ø 3.0 → 2.5 mm, Ø 4.4 → 4.0 mm). With a different layer height, material or printer, check the fit with the step test first.

Step test `knx-box-case-insert-step-test.stl`: five bosses and five columns as in the case. The embossed dots (1–5) between the rows indicate the column:

| Dots | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| M2.5 boss, hole | 3.3 | **3.4** | 3.5 | 3.6 | 3.7 |
| M3 column, hole | **4.5** | 4.6 | 4.7 | 4.8 | 4.9 |

The right column is the one where the insert just stands in the hole with its smooth end and sits firmly after melting in, without turning.

## Assembly

### Parts list

| Qty | Part | Purpose |
|---|---|---|
| 4 | Heat-set insert M2.5 × 4 (CNC Kitchen) | into the bosses of the base |
| 4 | Heat-set insert M3 × 4 (CNC Kitchen) | into the corner columns of the lid |
| 2 | Screw M2.5 × 6 | Pi, back, into the inserts |
| 2 | Screw M2.5 × 16 | through module bridge and Pi, front, into the inserts |
| 4 | Screw M3 × 8, socket head ISO 4762 (head ≤ 5.5 mm) | lid, from below into the inserts |
| 1 | Module bridge (printed) | supports the kBerry |
| 1 | USB cover (printed, optional) | closes unused USB sockets |
| 2 + 2 | DIN rail only: heat-set insert M3 × 4 and screw M3 × 6 ISO 7380 | latch clip on the DIN-rail base |

### Step 1: inserts

Base and lid lie on their closed side, so the lid upside down. Set the inserts flush from above with a soldering iron and let them cool.

### Step 2: assembly

1. Remove the rubber dot under the front end of the kBerry.
2. Put the Pi on the bosses. One M2.5 × 6 into the inserts at the back left and back right.
3. Place the module bridge on the two front Pi holes and screw it with two M2.5 × 16 from above through bridge and Pi into the inserts. The heads disappear in the counterbores.
4. Plug the kBerry onto GPIO pins 1–26. It rests on the bridge at the front.
5. Put on the lid. The skirt wraps around the terminal.
6. Screw the four M3 × 8 from below through the corners of the base into the inserts of the lid. The heads sit recessed (counterbore Ø 5.8 × 3.5 mm). Hole spacing 91.8 × 60.8 mm.
7. Lead the bus cable through the wire channel to the terminal.
8. Optionally plug in the USB cover.

## Fit test `knx-box-case-fit-test.stl`

A quick-to-print template: a 1.2 mm thin lid plate above the module with terminal opening, skirt, pin hole, pockets and guides in their original positions, plus a piece of the left wall with the wire channel.

1. Assemble Pi and kBerry without the module bridge. Fit test and bridge both use the front right Pi hole.
2. Put on the fit test. Its two feet stand above the two right Pi holes.
3. From below, screw one M2.5 screw (6–8 mm) each through the Pi holes into the pilot holes of the feet (Ø 2.2 mm, the screw cuts its own thread).
4. Check:
   - Do the guides slide past the module edges without jamming?
   - Does the terminal sit freely in the opening without jamming on the skirt?
   - Does the skirt stay above the components next to the terminal?
   - Does the pin hole meet the button?
   - Do the capacitors collide?

The plate of the fit test is thinner than the ceiling, so the terminal protrudes further there (3.7 instead of 2.4 mm).

## Cooling

- About 11 mm remain between the top of the Pi and the underside of the kBerry.
- The official Pi 5 Active Cooler very likely does not fit there.
- Flat, adhesive passive heat sinks up to about 8 mm high on the SoC fit. An 8 mm heat sink is checked against the case.
- The box settings in the app show the SoC temperature, its maximum since start, under-voltage and throttling ([docs/knx-box.md](../../docs/knx-box.md#temperature-and-power-supply)). Use them to check a case before relying on it.

## Printing

- **Material:** PETG or ASA. PLA quickly becomes brittle with heat and impacts and is too weak for job-site use.
- **Orientation:** as in the STLs. The base lies on its underside, the lid on its top, the USB cover on its outer side. The module bridge lies on the top of its beam.
- **Walls:** 4–5 perimeters, 20–40 % infill (gyroid). For drop resistance, prefer more perimeters over more infill.
- **Layer height:** 0.2 mm. The insert holes are tuned to this layer height.
- **Outer surfaces:** the top of the lid and the underside of the base get the surface of the print bed.
- **Closed meshes:** all STLs have no open edges (checked by edge count). No repair in the slicer is needed.
- **Strings in the wire channel:** retraction or "avoid crossing walls" in the slicer prevents strings across the gap.

## Verified

- **In the model, individually against base, lid and fit test:**
  - Pi 3B+, 4B and 5 with all sockets.
  - The kBerry with board, terminal, button, capacitors, optocouplers, header and the SMD parts next to the terminal.
  - An 8 mm heat sink.
  - The module bridge additionally against USB-C, HDMI (including the full-size one of the Pi 3), audio, camera and MIPI connectors and the Pi 5 PoE pins.
- **Counter-checks:** a module that shifts 0.5 mm sideways or lifts by 0.7 mm hits a guide or the skirt. One that sits 0.3 mm lower rests on the bridge.
- **On the print:**
  - Base and module bridge are assembled.
  - The terminal window was adjusted after the first fit test.
  - First build with the slim lid: the front left guide, the front end of the right guide and both hold-downs had to go, and the skirt hit the SMD part in front of the terminal. Both are fixed in the model.
  - The insert holes are determined with the step test at 0.2 mm layer height.

## Open points

- Slim lid with skirt and pin hole on a real build.
- USB cover on a Pi.
- Latch clip: variant 1 (`clip-1`) is chosen and still being refined. After that `clip-2` and `clip-3` go away.
- Drop test from 1 m.
- The kBerry status LEDs are not visible with the lid closed.
- The case is not sealed and has no IP rating.
