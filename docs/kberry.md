# KNX TP on a Raspberry Pi with the Weinzierl kBerry

This guide describes how Busclear connects to a KNX twisted-pair (TP) bus through the
Weinzierl **KNX BAOS Module 838 "kBerry"** plugged onto a Raspberry Pi, without a KNXnet/IP
gateway. It covers the hardware, the Raspberry Pi configuration, the serial protocol (FT1.2
with cEMI), the two operating modes (link layer and bus monitor), diagnostics, known pitfalls,
and a map of the code.

The implementation is plain Dart with no native dependencies. It runs inside the Busclear
server on the Raspberry Pi box image (`box/`). It is written so that the transport can be
reused in other projects. The code is licensed under the **GNU GPL v3** (see
[`LICENSE`](../LICENSE)); reuse is welcome under that licence.

All paths below are relative to the repository root. Server code lives in
`ha-addon/knx_monitor/server/` (abbreviated as `server/` below).

## Contents

1. [Summary](#1-summary)
2. [Hardware](#2-hardware)
3. [Raspberry Pi configuration](#3-raspberry-pi-configuration)
4. [Serial protocol: FT1.2](#4-serial-protocol-ft12)
5. [cEMI management: properties and modes](#5-cemi-management-properties-and-modes)
6. [Connection lifecycle](#6-connection-lifecycle)
7. [Sending and receiving group telegrams](#7-sending-and-receiving-group-telegrams)
8. [Bus monitor mode](#8-bus-monitor-mode)
9. [Diagnostics: the `hat` probe](#9-diagnostics-the-hat-probe)
10. [Limitations and pitfalls](#10-limitations-and-pitfalls)
11. [Code map and tests](#11-code-map-and-tests)
12. [Alternatives considered](#12-alternatives-considered)
13. [References](#13-references)

## 1. Summary

- The kBerry is **not** a TP-UART chip. It runs its own certified KNX stack (System B) with a
  BAOS object server and talks to the host over a **galvanically isolated UART** on GPIO 14/15.
- The host protocol is **FT1.2** (IEC 60870-5-1/-2) at **19200 baud, 8E1**. Inside the FT1.2
  frames the module speaks either the BAOS protocol or **cEMI**.
- Writing cEMI property **PID 52 (communication mode)** of the cEMI server object switches the
  module to **link layer** (`0x00`: send and receive `L_Data`) or **link-layer bus monitor**
  (`0x01`: receive every frame on the wire, *including* ACK/NAK/BUSY, but no sending).
  `0xF0` switches back to BAOS mode.
- Busclear implements this as `Ft12CemiLink` (`package:knx_io`, `lib/src/ft12_link.dart`), a
  `BusLink` like the KNXnet/IP tunnel. Everything above it (recording, watchers, WebSocket
  clients) is unchanged.
- On the Raspberry Pi the PL011 UART must be routed to GPIO 14/15 as `/dev/ttyAMA0`, and the
  serial console must be off. `box/setup.sh` does this for Pi 4 and Pi 5.
- Field-tested on a Raspberry Pi 4 against a real bus: both modes work, the bus monitor
  delivers acknowledgements with status and timestamp. The Pi 5 configuration follows the
  Raspberry Pi documentation but has not been tested on a bus yet.

## 2. Hardware

### Module data

From the Weinzierl datasheet and the enclosed product leaflet:

| Item | kBerry 838 |
|---|---|
| Board | 56 × 35 mm, 8 mm high without connector, about 12 g, **no mounting holes** (held only by the header) |
| Connector | 26-pin female header on pins 1–26 of the Pi's 40-pin header (fits Pi 2 to Pi 5) |
| Pins used | 1 VCC (3.3 V), 6 GND, 8 RX of the module (= GPIO 14, TXD of the Pi), 10 TX of the module (= GPIO 15, RXD of the Pi) |
| Bus connection | standard KNX terminal (red/black) on the board |
| Supply | KNX side powered from the bus (3 mA per the 2025 leaflet; older datasheets say 10 mA); the Pi side only powers the isolated UART from 3.3 V |
| Isolation | galvanic isolation between bus and Pi, SELV DC 29 V |
| Host interface | UART 19200 or 115200 baud, 8E1, FT1.2 framing, BAOS protocol V2 or cEMI |
| KNX stack | certified System B, long frames up to APDU 55, up to 1000 group objects |
| Controls | programming button and LED, LEDs for power, KNX and host |
| Environment | −5 to +45 °C operating, 5–93 % RH non-condensing |

The kBerry does **not** power the Pi. The Pi needs its own supply; use one with safe isolation
(for example a DIN-rail supply) when mounting in a distribution board. The module only answers
when bus voltage is present; "no answer" without bus voltage is normal and should be reported
as "no bus", not as a defect.

### Mounting and wiring

Pinout and photos are in the *KNX BAOS Starter Kit User's Guide* (pp. 77, 79, 112).

1. Power off the Pi. Do not connect the bus yet.
2. Find pin 1 on the Pi: on Pi 2 to Pi 5 it is the end of the 40-pin header **away from the
   USB/Ethernet ports**, in the **inner row** (towards the board centre). It has a square pad
   on the underside.
3. Find pin 1 on the kBerry: the component side is marked "1" and "VCC" next to the header,
   "GND" opposite.
4. Plug the 26-pin socket onto **pins 1–26**, flush with the pin-1 end. Pins 27–40 stay free.
   The module lies over the Pi board; its bus terminal sits on the pin-1 side towards the
   microSD card. Correctly seated, kBerry pins 1/6/8/10 land on Pi pins 1 (3.3 V), 6 (GND),
   8 (GPIO 14, TXD) and 10 (GPIO 15, RXD).
5. Check before powering up: every socket sits on a pin, nothing is offset by a row or column.
   Offset by one row, VCC lands on pin 2 (**5 V**). If the module overhangs the board edge
   instead of lying over it, it is rotated by 180° (pins 15–40).
6. Connect the bus: red = +, black/grey = −. With bus voltage the power LED lights. KNX and host
   LEDs may stay dark until software talks to the module.
7. Configure the UART (section 3) before the first boot with the module, otherwise a Pi 4
   prints boot messages into it (harmless, but it confuses the first test).

Reversed polarity at the bus terminal is the most frequently reported fault in community
threads.

Because the module has no mounting holes, it needs mechanical support in an enclosure subject to
vibration. The 3D-printed case in [`box/case/README.md`](../box/case/README.md) uses a printed
bridge under the front end of the module, keeps about 11 mm between Pi and kBerry, and leaves
the bus terminal reachable through the lid. The Pi 5 Active Cooler sits directly under the
module; whether it fits has not been checked. An illustrated mounting guide is built from
`docs/pdf/knx-hat/` with `docs/pdf/knx-hat/build.sh` and published as
`site/static/box/knx-box-kberry.pdf`.

## 3. Raspberry Pi configuration

The kBerry always sits on GPIO 14/15. Which UART is connected there depends on the model
([Raspberry Pi documentation: Configure UARTs](https://www.raspberrypi.com/documentation/computers/configuration.html#configure-uarts)):

| | Pi 4 | Pi 5 |
|---|---|---|
| Default on GPIO 14/15 | mini UART (`ttyS0`); the PL011 (`ttyAMA0`) is used by Bluetooth | nothing; PL011 `UART0` is off, the console is on the debug connector (`ttyAMA10`) |
| Setting | `dtoverlay=disable-bt` and disable `hciuart`; PL011 becomes `ttyAMA0` on GPIO 14/15 | `dtoverlay=uart0-pi5` (or `dtparam=uart0=on`); `ttyAMA0` on GPIO 14/15, Bluetooth has its own UART |
| Device | `/dev/ttyAMA0` (`/dev/serial0` points to it) | `/dev/ttyAMA0` (`/dev/serial0` points to `ttyAMA10`) |
| Pitfall | The mini UART depends on the VPU clock and has no parity, so it is unusable for 8E1. Do not use `miniuart-bt` for the kBerry. | **Do not set `enable_uart=1`**: without a cable on the debug connector the Pi 5 then sends kernel output to GPIO 14/15, i.e. into the module. |

One configuration covers all models, with `/dev/ttyAMA0` as the fixed device. The Pi 3 routes
the PL011 to Bluetooth like the Pi 4 and gets the same overlay. This is what `box/setup.sh`
appends to `config.txt` (once, guarded by a `# KNX-HAT` marker; boxes set up before 1.9.4 get
the `[pi3]` section added on update):

```ini
# /boot/firmware/config.txt
[pi3]
dtoverlay=disable-bt
[pi4]
dtoverlay=disable-bt
[pi5]
dtoverlay=uart0-pi5
[all]
```

`box/setup.sh` additionally:

- removes `console=serial0,<baud>` from `/boot/firmware/cmdline.txt` (pi-gen adds it by
  default; on a Pi 4 the console would otherwise talk to the module),
- runs `systemctl disable hciuart.service` and `systemctl mask serial-getty@ttyAMA0.service`,
- adds the service user to `dialout` (`/dev/ttyAMA0` is `root:dialout`, mode 0660),
- asks for one reboot when it changed boot files.

None of this harms a Pi without a kBerry: the UART is simply unused.

### systemd sandbox

The service unit [`box/files/knx-box.service`](../box/files/knx-box.service) runs the server
hardened. `PrivateDevices=yes` would hide the UART, so the unit grants access to the serial
devices only: the Pi's UART and USB serial adapters.

```ini
PrivateDevices=no
DevicePolicy=closed
DeviceAllow=char-ttyAMA rw
DeviceAllow=char-ttyUSB rw
DeviceAllow=char-ttyACM rw
SupplementaryGroups=dialout
```

`RestrictAddressFamilies` stays in place; a serial port needs no socket.

### Notes from the vendor guide

The Weinzierl guide (ch. 13.3.2, written for older Raspbian) recommends `miniuart-bt` for
Pi 3/4 and additional `gpio=3,18,17,22,24=ip,pu` / `gpio=2,4,27,23,25=op,dl` lines. According
to the datasheet the kBerry uses only VCC, GND, RX and TX. Busclear works without the
`gpio=` lines on a Pi 4; their purpose is unclear.

### Quick checks without the server

```sh
ls -l /dev/ttyAMA0 /dev/serial0
cat /proc/cmdline                               # must not contain console=serial0
systemctl status hciuart serial-getty@ttyAMA0   # both inactive
# Loopback test without the module: bridge pins 8 and 10, then type and see the echo
picocom -b 19200 -y e /dev/ttyAMA0
```

`picocom` is part of the box image (`box/pi-gen/stage-knx-box/00-knx-box/00-packages`).

## 4. Serial protocol: FT1.2

Reference: *KNX BAOS Starter Kit User's Guide*, ch. 5.4; implementation in
[`knx_io: lib/src/ft12.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/ft12.dart) and
`Ft12Session` in [`knx_io: lib/src/kberry.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/kberry.dart).

### Line settings

19200 baud, 8 data bits, even parity, 1 stop bit, raw mode, no flow control. The module can be
switched to 115200 baud (BAOS server item 13), and it falls back to 19200 after a bus voltage
failure. Busclear never changes the rate; it tries **19200 first, then 115200**
(`bauds` in `Ft12CemiLink` and `KberryProbe`).

`TtyLine.open` configures the device with `stty` and reads it as a file:

```sh
stty -F /dev/ttyAMA0 raw 19200 cs8 parenb -parodd -cstopb -crtscts clocal cread -echo min 0 time 1
```

`min 0 time 1` makes every `read()` return after at most 100 ms, even with no data. That
keeps reads cancellable without a separate isolate or `dart:ffi`. Two details matter:

- Existence is checked with `File(device).exists()`, because `FileSystemEntity.type` reports
  character devices as `notFound`.
- The write handle is opened with `FileMode.writeOnly`. Append mode seeks to the end, which a
  tty rejects with `ESPIPE`.

### Frames

| Frame | Bytes | Meaning |
|---|---|---|
| Reset | `10 40 40 16` | Resets protocol counters and state only, not the module |
| Data | `68 L L 68 C <data> CS 16` | `L` = length of `C` + data; `CS` = sum of `C` + data, mod 256 |
| Acknowledge | `E5` | Single character, acknowledges a reset or a data frame |

Control byte `C`:

| Direction | FCB set | FCB clear |
|---|---|---|
| Host → module | `0x73` | `0x53` |
| Module → host | `0xF3` | `0xD3` |

Bit 5 is the **frame count bit (FCB)**. The sender toggles it for every *new* frame and keeps it
for a repetition. After a reset the host's first frame has the FCB set.

Example from the Weinzierl guide (read the serial number, FCB clear), reproduced in
`server/test/kberry_test.dart`:

```text
68 08 08 68 53 FC 00 00 01 0B 10 01 6C 16
```

### Acknowledgements, retries, timing

`Ft12Session` implements the host side:

| Operation | Behaviour | Timeout |
|---|---|---|
| `reset()` | Send `10 40 40 16`, wait for `E5`; set FCB, forget the last received frame | 600 ms |
| `send(data)` | Send a data frame, wait for `E5`, toggle FCB on success; **one retry** with the same FCB | 500 ms per attempt |
| `ask(request, code)` | `send()`, then wait for a data frame whose first byte (cEMI message code) is `code` | 1500 ms |
| `read()` on the line | Returns whatever arrived | ≤ 100 ms (`stty time 1`) |

Receiving side:

- **Every** data frame from the module is acknowledged with `E5` immediately, before it is
  handed on (`Ft12Session._fill`).
- If the module repeats a frame with the same control byte and identical content (our `E5` was
  lost), it is acknowledged again but delivered only once.
- `Ft12Decoder` resynchronises on garbage: unknown bytes and frames with a bad checksum or end
  byte are skipped one byte at a time and counted in `skipped` (reported by the probe as
  `skippedBytes`). Frames split across reads are reassembled.

The session only reads when somebody waits (`poll`, `ask`, `collect`). Data frames that arrive
while waiting for an `E5` or a specific answer are queued, not dropped, and returned by the
next `poll()`.

## 5. cEMI management: properties and modes

Inside FT1.2, Busclear uses cEMI local device management
(KNX specification 03.06.03 EMI/IMI; Weinzierl guide ch. 4.6.1.7 and 5.2).

### Property services

`Ft12Session.readProperty` and `writeProperty` always address instance 1, one element, start
index 1:

```text
M_PropRead.req   FC <objType:2> 01 <PID> 10 01
M_PropRead.con   FB <objType:2> 01 <PID> <NoE|SIX:2> <value…>
M_PropWrite.req  F6 <objType:2> 01 <PID> 10 01 <value…>
M_PropWrite.con  F5 <objType:2> 01 <PID> <NoE|SIX:2> [error code]
```

A confirmation whose number of elements (high nibble of byte 5) is 0 is a negative response;
both methods then return `null` or `false`.

### Properties used

| Object | PID | Name | Use |
|---|---|---|---|
| Device (`0x0000`) | 11 (`0x0B`) | Serial number | Read by the probe |
| Device (`0x0000`) | 57 (`0x39`) | Subnet address (area/line) | Read and optionally written for the individual address |
| Device (`0x0000`) | 58 (`0x3A`) | Device address | Read and optionally written for the individual address |
| cEMI server (`0x0008`) | 52 (`0x34`) | Communication mode | `0x00` link layer, `0x01` bus monitor, `0xF0` back to BAOS |
| cEMI server (`0x0008`) | 64 (`0x40`) | Supported communication modes (16 bit) | Bit 0 link layer, bit 1 bus monitor, bit 3 transport layer |

The value `0x01` for bus monitor is not spelled out in the Weinzierl guide; it follows the KNX
specification and was confirmed on a real module. A kBerry tested on a Pi 4 reported PID 64 =
`0x000B` (link layer, bus monitor, transport layer) and PID 52 = `0xF0` after power-up.

### Other messages

| Code | Name | Handling |
|---|---|---|
| `A7` / `A8` | PEI identify request / response | Sent once after reset; a Weinzierl module in cEMI mode answers with 11 bytes instead of 9 (other stacks use this to detect cEMI). Busclear only requires *an* answer. |
| `F0` | `M_Reset.ind` | Module restarted (ETS download, bus voltage loss). It is back in BAOS mode; the link treats the connection as lost. |

### Example: switching to link layer

The frames `Ft12CemiLink.connect` sends when no individual address is requested (FCB
alternating from set):

```text
10 40 40 16                                     reset                 ← E5
68 02 02 68 73 A7 1A 16                         PEI identify          ← E5, A8 …
68 08 08 68 53 FC 00 08 01 40 10 01 A9 16       read PID 64           ← E5, FB …
68 08 08 68 73 FC 00 00 01 39 10 01 BA 16       read PID 57           ← E5, FB …
68 08 08 68 53 FC 00 00 01 3A 10 01 9B 16       read PID 58           ← E5, FB …
68 09 09 68 73 F6 00 08 01 34 10 01 00 B7 16    write PID 52 = 0x00   ← E5, F5 …
```

For the bus monitor the last value is `01`; to return to BAOS it is `F0`. Every data frame the
module sends back is acknowledged with `E5` by the host.

## 6. Connection lifecycle

`Ft12CemiLink` ([`knx_io: lib/src/ft12_link.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/ft12_link.dart))
implements the `BusLink` interface from
[`knx_io: lib/src/link.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/link.dart):
`connect()`, `frames` (stream of cEMI frames), `send(cemi)`, `lost` (future completing with a
reason), `close()`, `address`, `label`.

Constructor parameters: `open` (a function returning a `SerialLine` for a baud rate),
`device` (default `/dev/ttyAMA0`), `busmonitor`, `requestedAddress`,
`bauds` (default `[19200, 115200]`), `keepalive` (default 30 s), `confirmTimeout`
(default 3 s).

### connect()

1. Wait until no previous link or running probe holds the same device (see *Exclusive use of
   the UART* below).
2. For each baud rate: open the line and send an FT1.2 reset. The first rate that gets an
   `E5` wins (`baud`). No answer at any rate fails with "does not respond (bus voltage, slot,
   UART?)".
3. PEI identify (`A7`); no `A8` answer fails.
4. Read PID 64. If the mask is present and lacks the requested mode, fail with a clear message.
   If the module does not answer PID 64, the link continues.
5. Individual address: only in link-layer mode and only if `requestedAddress` is set, write
   PID 57 and 58 (skipped if already equal). Then read PID 57/58 into `address` (factory
   default `15.15.255`).
6. Write PID 52 (`0x00` or `0x01`). Rejection fails.
7. Start the pump loop.

Any failure after step 2 restores BAOS mode (`PID 52 = 0xF0`) and closes the line before the
exception propagates, so the module is never left in link-layer or monitor mode.

### The pump loop

A single loop owns the line (`_pump`). Each iteration:

1. runs at most one queued job (send a telegram or a keepalive check),
2. polls the line once (≤ 100 ms) and dispatches the received frames,
3. queues a keepalive job if nothing was heard for `keepalive`.

Dispatch by cEMI message code:

| Code | Name | Action |
|---|---|---|
| `0x29` | `L_Data.ind` | emitted on `frames` |
| `0x2B` | `L_Busmon.ind` | emitted on `frames` |
| `0x2E` | `L_Data.con` | matched to a pending send, then emitted on `frames` |
| `0xF0` | `M_Reset.ind` | connection lost ("restarted") |

Serialising everything through one loop avoids concurrent reads on the tty and keeps FT1.2
acknowledgements in order.

### Keepalive and loss detection

After `keepalive` (30 s) without any data frame, the loop reads PID 52. `lost` completes when

- the read fails (I/O error, module unplugged),
- the module sends `M_Reset.ind`,
- the module does not acknowledge a frame after the retry,
- the keepalive read gets no answer, or PID 52 no longer holds the requested mode.

On loss or `close()` the link fails pending sends, drains the job queue, writes PID 52 =
`0xF0`, closes the line and closes `frames` (`_release`, run once). The owner (`BusService`)
then reconnects the same way it rebuilds a lost KNXnet/IP tunnel.

### Exclusive use of the UART

Only one user may talk FT1.2 on the line at a time. A static map `_releasing` per device
records pending shutdowns: a new `Ft12CemiLink` on the same device waits until the old one
has restored BAOS mode and closed the line. `Ft12CemiLink.occupy(device, future)` lets other
users (the diagnostic probe, section 9) claim the device in the same way.

## 7. Sending and receiving group telegrams

### Receiving

In link-layer mode the module delivers standard cEMI `L_Data.ind` frames, identical to what a
KNXnet/IP tunnel delivers, so the rest of the server handles them unchanged. Example from the
simulated module (`server/test/fake_kberry.dart`), a GroupValueWrite from 1.1.5 to 1/1/1 with
value 1:

```text
29 00 BC E0 11 05 09 01 01 00 81
```

Whether the module itself acknowledges telegrams on the bus while in link-layer mode (other
than those addressed to its own individual address) has not been verified. Without an ETS
download its group table is empty.

### Sending

`send(cemi)` accepts an `L_Data.req` (`0x11`, at least 10 bytes) and

1. rejects it in bus-monitor mode,
2. overwrites the source address with the module's own address (like a tunnel does),
3. queues a job that sends it through FT1.2; if the module does not acknowledge, the send fails
   *and* the connection is dropped,
4. waits up to `confirmTimeout` (3 s) for an `L_Data.con` with the same destination address.
   The oldest pending send with that destination is completed. Without a confirmation the send
   fails, but the connection stays up.

Example: GroupValueWrite to 1/2/3 with value 0, as cEMI and in its FT1.2 frame:

```text
11 00 BC E0 00 00 0A 03 01 00 80
68 0C 0C 68 73 11 00 BC E0 00 00 0A 03 01 00 80 AE 16
```

On a Pi 4 a GroupValueRead was confirmed after 147 ms and both responses arrived; the
connection itself took 170 ms at 19200 baud.

### Individual address

The module has its own individual address in the device object (PID 57/58), `15.15.255` from
the factory. With `requestedAddress` the link writes it before switching modes. The address
appears in the link label (for example `KNX-HAT Link Layer 15.15.255`) and is used as the
source of every sent telegram. Choose an address that is free on the line, as for any
interface.

## 8. Bus monitor mode

With PID 52 = `0x01` the module delivers every frame seen on the wire as `L_Busmon.ind`
(`0x2B`), including the one-byte acknowledgement frames, with additional info:

| Additional info | Length | Content |
|---|---|---|
| `0x03` | 1 | Bus monitor status: bits 0–2 sequence number; bit 3 lost, 4 overflow, 5 parity error, 6 bit error, 7 frame error (KNX 03.06.03) |
| `0x04` | 2 | Relative timestamp |

The raw TP frame follows the additional info. Acknowledgement frames are one byte:

| Byte | Meaning |
|---|---|
| `0xCC` | ACK |
| `0x0C` | NAK |
| `0xC0` | BUSY |
| `0x00` | NAK + BUSY |

Example from the tests: a GroupValueWrite 1.1.5 → 1/1/1 with status and timestamp, then an ACK:

```text
2B 07 03 01 00 04 02 12 34 BC 11 05 09 01 E1 00 81 3F
2B 00 CC
```

In this mode sending is impossible; `send` throws.

### How Busclear uses monitor frames

`BusService._handleFrame` (`server/lib/src/bus.dart`):

- forwards every raw `0x2B` frame to WebSocket clients, which render the bus monitor view,
- counts it in `BusmonCounters` (data, ACK, NAK, BUSY, damaged, *orphan ACKs*: an ACK
  with no data frame directly before it, and *sequence gaps*: frames skipped by the sequence
  number in the status byte; the count starts again after every reconnect),
- converts error-free standard data frames with a valid checksum into `L_Data.ind` with
  `busmonToLData` (`ft12_link.dart`), so recording, watchers and the group monitor work as
  with a tunnel. ACKs, damaged frames (status bits 3–7 set or bad checksum), extended frames
  and truncated frames are not converted. The repeat flag is kept.

The counters appear in `/api/bus` status (`busmon`) and per day in
`status/busmon-<day>.json`.

### Bandwidth

At 19200 baud 8E1 (11 bits per byte) the line carries about 1745 bytes/s. In monitor mode
every bus frame, including every one-byte ACK, carries cEMI header, additional info and FT1.2
framing (roughly 15–20 bytes of overhead). At bus loads well above 50 % this may become tight.
This is an estimate, not a measurement.

### Missing data frames (measured 7 November 2026)

In bus monitor mode the kBerry leaves out about **every second data frame**. The
acknowledgement that follows it arrives, and the sequence number in the status byte skips the
missing frame, so the module saw it and did not pass it on.

Measured on the test box (Pi 4, kBerry firmware as delivered, line 1.1 with about 30 group
telegrams per minute), with a small Python tool that talks FT1.2 through termios and
acknowledges every frame at once, and in parallel a KNXnet/IP tunnel to a Gira X1 on the same
line as the reference:

| Run | Data frames on the bus (tunnel) | Delivered by the kBerry | ACK without data frame | Sequence gaps |
|---|---|---|---|---|
| Bus monitor, 19200 baud, 60 s | 31 | 19 | 11 | 10 |
| Bus monitor, 115200 baud, 60 s | 16 | 6 | 10 | 9 |
| Link layer, 19200 baud, 120 s (box recording) | 31 | 31 | – | – |

What this rules out:

- **Not the host.** The Python tool acknowledges within a millisecond, the Dart server shows
  the same rate, and the raw log contains no damaged or skipped bytes.
- **Not the bandwidth.** 115200 baud does not help, and frames go missing after more than a
  second of silence on the line as well.
- **Not the frame.** The same telegram (source, destination, value) arrives in one run and is
  missing in another; group reads, responses and writes are all affected.
- **Not reception.** In link layer mode the module delivers every group telegram the gateway
  sees.

A likely explanation is that the module's bus monitor path keeps only one frame at a time and
the acknowledgement, 1.5 ms after the end of the data frame, overwrites it. This is an
inference from the pattern, not confirmed by Weinzierl. The module offers no other mode that
would help (PID 64 = `0x000B`: link layer, bus monitor, transport layer; raw mode is rejected).

Consequences in Busclear:

- **Record in link layer mode.** It is the default and complete. The bus monitor is for
  acknowledgements, NAK/BUSY, repetitions and damaged frames; recording, watchers and the group
  monitor see only about half of the telegrams there. The connection settings say so next to
  the switch.
- `BusmonCounters` reports `orphanAcks` and `seqGaps` in the status (`busmon`) and per day; the
  `hat` probe reports both in the `busmonitor` step.
- The app's bus monitor shows a notice from the first acknowledgement without a data frame.
  Missing frames are counted, never invented.

## 9. Diagnostics: the `hat` probe

`KberryProbe` (`server/lib/src/kberry.dart`) runs a fixed sequence against the module and
returns a JSON report. Steps (`kberrySteps`):

| Step | What it does | Status |
|---|---|---|
| `reset` | FT1.2 reset at 19200, then 115200; records each attempt and skipped bytes | `fail` stops the run |
| `identify` | PEI identify; reports response and length | `warn` without answer |
| `serial` | Read PID 11 | `warn` without answer |
| `modes` | Read PID 64; reports `linkLayer`, `busmonitor`, `transportLayer` | `warn` without bus monitor |
| `commMode` | Read PID 52 | `warn` without answer |
| `linkLayer` | PID 52 = `0x00`, collect `L_Data.ind` for the listen time | `warn` if nothing heard |
| `busmonitor` | PID 52 = `0x01`, collect and classify `L_Busmon.ind` (`classifyBusmon`: ACK, NAK, BUSY, NAK+BUSY, data, repeated, error bits, timestamps, ACKs without a data frame, sequence gaps) | `ok` only if at least one ACK was seen; gaps are reported, not graded, because every kBerry has them |
| `restore` | PID 52 = `0xF0` | `warn` if rejected |

The module is always returned to BAOS mode, also after an exception, and the line is closed.

`kberrySystem(device)` adds a system check: device present and openable, serial console in
`/proc/cmdline`, relevant `config.txt` lines (`disable-bt`, `miniuart-bt`, `uart0-pi5`,
`dtparam=uart0`, `enable_uart=`), and the Pi model.

### Running it

From a shell on the Pi (`server/bin/server.dart`):

```sh
sudo -u knx-box /opt/knx-box/server hat 10
```

The argument is the listen time per step in seconds (default 10, clamped to 1–120). Progress
goes to stderr, the report (`system` and `report`) to stdout. This path does **not** check
whether the running service holds the UART; stop the service first if it is connected through
the kBerry (`sudo systemctl stop knx-box`).

Through the HTTP API (admin only, box image only):

- `GET /api/box/hat` returns the system check, the running step and the last report.
- `POST /api/box/hat` with `{"seconds": n}` (clamped to 3–60) starts a probe in the
  background. It answers `409` with `"busy": "link"` while the bus connection uses the kBerry,
  and `409` if a probe is already running. While a probe runs, a kBerry link waits for it
  (`KberryService.start` calls `Ft12CemiLink.occupy`).

The app shows this as a test page (`lib/ui/box_hat_screen.dart`).

### Configuration in the server

`BusConfig` (`server/lib/src/bus.dart`) selects the kBerry with `mode: "hat"`:

| Field | Meaning |
|---|---|
| `device` | Serial device; only `/dev/tty…` or `/dev/serial<n>` are accepted, otherwise `/dev/ttyAMA0` |
| `hatAddress` | Individual address as `a.l.d`, or `null` to keep the module's |
| `hatBusmonitor` | `true` for bus monitor mode |

`defaultLink` builds an `Ft12CemiLink` with `TtyLine.open` for this mode. The status reports
`hat: {device, present}` on the box so clients only offer the mode when the device exists.

## 10. Limitations and pitfalls

- **Box image only.** The Home Assistant add-on image is built `FROM scratch` and has no `stty`;
  its `config.yaml` does not request `uart: true`. `BusService.update` rejects `mode: hat`
  when no HAT device is configured, rather than looping on failures
  (`server/test/busmon_counters_test.dart`). Supporting the add-on would require replacing
  `stty` with termios calls via `dart:ffi` (or shipping `stty`) and testing UART access under
  Home Assistant OS.
- **Baud rate.** The code detects 19200 or 115200 on every connect and never sets the rate
  itself. Setting it works in BAOS mode with `SetServerItem.Req` for server item 13 (`0x01`
  19200, `0x02` 115200): `F0 02 00 0D 00 01 00 0D 01 02`, answered with `F0 82 00 0D 00 00 00`,
  after which the module answers only at the new rate. Tested on 7 November 2026: the setting
  survives a module restart (`M_Reset.req`), the server finds the new rate by itself, and link
  layer and bus monitor work at 115200. It does not reduce the missing data frames (section 8).
  Whether a real loss of bus voltage resets the rate to 19200 is not tested; the server would
  find either rate.
- **Pi 3 untested on a bus.** `setup.sh` configures it like the Pi 4 (`dtoverlay=disable-bt`);
  the case fits a Pi 3B/3B+.
- **Pi 5 untested on a bus.** The overlay and `ttyAMA0` mapping follow the Raspberry Pi
  documentation.
- **Confirmations are matched by destination only.** `L_Data.con` completes the oldest pending
  send with the same destination address. A negative confirmation (confirm bit in control
  field 1 set, nobody acknowledged on the bus) fails that send with a `LinkException`
  (`server/test/ft12_link_test.dart`).
- **FT1.2 acknowledgements are not correlated.** Any `E5` received while waiting counts as the
  acknowledgement of the frame just sent.
- **Standard frames only for recording.** `busmonToLData` ignores extended frames in bus
  monitor mode; `send` accepts any `L_Data.req` of at least 10 bytes.
- **No tunnel to yield.** With a KNXnet/IP tunnel the server can release its tunnel so a client
  opens its own bus monitor. With the kBerry there is only one interface; the bus monitor comes
  from the server (`hatBusmonitor`), and link layer and monitor cannot run at the same time.
- **Module restart.** After an ETS download or bus voltage loss the module sends
  `M_Reset.ind` and returns to BAOS mode; the link drops and reconnects at once, trying both
  baud rates. Field test on 7 November 2026: a cEMI `M_Reset.req` written beside the running
  server made it report „KNX-HAT neu gestartet“ and reconnect within 2 s, recording continued.
  A power cut of box and bus together (6/7 November 2026, about 8 hours) was also survived. A
  loss of bus voltage alone while the Pi keeps running has not been tested on the bus yet (one
  community report needed a restart of Pi and bus power supply); `ft12_link_test.dart` covers
  the restart with a changed baud rate.
- **Shutdown can hang on a stuck line.** The server's signal handler limits cleanup to 8 s so
  that systemd does not kill it hard (`server/bin/server.dart`).
- **Common field failures** reported by others: reversed bus polarity, console or Bluetooth
  still on the UART, "reset timed out" without obvious cause, and the module not answering
  without bus voltage. Check step by step with the probe before debugging the server.
- **Operating temperature** ends at +45 °C, which can be tight in a distribution board in
  summer.

## 11. Code map and tests

### Source

| File | Contents |
|---|---|
| [`knx_io: lib/src/ft12.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/ft12.dart) | FT1.2 constants (`ft12Ack`, `ft12Reset`), `ft12Frame` encoder, `Ft12Decoder` and its events. Pure functions, no I/O. |
| [`knx_io: lib/src/kberry.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/kberry.dart) | `SerialLine` interface, `TtyLine` (stty-based Linux tty), `Ft12Session` (ACK, FCB, retries, property services), `KberryProbe`, `classifyBusmon` |
| [`server/lib/src/kberry.dart`](../ha-addon/knx_monitor/server/lib/src/kberry.dart) | Box-specific: `kberrySystem`, `KberryService` (German report texts via `linkReport`) |
| [`knx_io: lib/src/ft12_link.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/ft12_link.dart) | `Ft12CemiLink` (the `BusLink`), `busmonToLData`, `BusmonCounters` |
| [`knx_io: lib/src/link.dart`](https://github.com/regetskcob/dart-knx/blob/main/packages/knx_io/lib/src/link.dart) | `BusLink` interface and `LinkException`, shared with the KNXnet/IP links |
| [`server/lib/src/bus.dart`](../ha-addon/knx_monitor/server/lib/src/bus.dart) | `BusConfig` fields for `hat`, `defaultLink`, monitor frame handling in `BusService` |
| [`server/bin/server.dart`](../ha-addon/knx_monitor/server/bin/server.dart) | `server hat [seconds]` command, `/api/box/hat` handler |
| [`server/lib/box.dart`](../ha-addon/knx_monitor/server/lib/box.dart) | Library export of the above for the box |
| [`box/setup.sh`](../box/setup.sh), [`box/files/knx-box.service`](../box/files/knx-box.service) | Pi UART configuration, service sandbox |
| [`lib/knx/busmon.dart`](../lib/knx/busmon.dart) | App-side parser for raw monitor frames (`BusmonFrame.fromRaw`) |

### Reusing the transport

The protocol part is published as the open-source package [`knx_io`](https://pub.dev/packages/knx_io) (BSD-3-Clause); Busclear keeps only the box-specific `kberry.dart` (`kberrySystem`, `KberryService`). The layering is deliberately thin so pieces can be taken individually:

- `ft12.dart` alone is enough to frame and parse FT1.2 in any Dart program.
- `Ft12Session` needs only a `SerialLine` (three methods: `write`, `read` with a short timeout,
  `close`). Provide your own implementation for another platform or serial library.
- `Ft12CemiLink` depends on `Ft12Session`, `link.dart` and `formatIndividual` from
  `package:knx`; it takes the line factory as a parameter (`open`), so it has no hard
  dependency on `TtyLine`.

### Tests

Run from `ha-addon/knx_monitor/server/`:

```sh
dart test test/kberry_test.dart test/ft12_link_test.dart test/busmon_counters_test.dart
```

| Test file | Documents |
|---|---|
| [`test/fake_kberry.dart`](../ha-addon/knx_monitor/server/test/fake_kberry.dart) | Simulated module behind a `SerialLine`: acknowledges reset and frames, answers PEI identify and property reads/writes (serial, PID 52/57/58/64), confirms `L_Data.req`, sends prepared frames after a mode switch. Knobs: wrong baud rate, `mute`, `restart()` (`M_Reset.ind`), `repeatLast()` (lost ACK), `rejectBusmon`, `confirmRequests`. Also `BrokenLine` and `FlakyKberry` for I/O errors. |
| [`test/kberry_test.dart`](../ha-addon/knx_monitor/server/test/kberry_test.dart) | Frame bytes from the Weinzierl guide, decoder reassembly and resynchronisation, all probe steps, baud fallback, missing bus monitor support, read errors, BAOS restore after abort, one probe at a time, character device detection |
| [`test/ft12_link_test.dart`](../ha-addon/knx_monitor/server/test/ft12_link_test.dart) | Link layer with sending and source address, writing the individual address, bus monitor, baud fallback, `M_Reset.ind`, mute module (keepalive), read errors, duplicate frames, missing confirmation, waiting for a previous link or a running probe, `busmonToLData`, `BusService` in `hat` mode, `BusConfig` validation |
| [`test/busmon_counters_test.dart`](../ha-addon/knx_monitor/server/test/busmon_counters_test.dart) | Bus monitor counters, and that the add-on cannot use the HAT |

## 12. Alternatives considered

- **knxd with the `ft12cemi` driver.** Available as a Debian package; it switches the kBerry to
  link layer and sets the address. It would have required no server changes, but its cEMI
  driver has no bus monitor mode, so ACK/NAK/BUSY would be invisible. It also adds a C++
  service and a local KNXnet/IP server. Good as a quick wiring test:
  `knxd -e 15.15.250 -E 15.15.251:4 -S -T -b ft12cemi:/dev/ttyAMA0`.
- **Weinzierl SDKs.** kDriveExpress (binary only, own licence) and the
  [BAOS SDK](https://github.com/weinzierl-engineering/baos) (C++, object-server level) do not
  fit a single Dart binary. The BAOS SDK is a useful reference for FT1.2 timing and
  initialisation.
- **Serial packages for Dart.** [`libserialport`](https://pub.dev/packages/libserialport) and
  [`dart_periphery`](https://pub.dev/packages/dart_periphery) work on ARM64 but add a native
  library. `stty` plus file I/O was enough.
- **TP-UART interfaces** (for example a USB TP-UART stick). They speak the TP-UART protocol
  with strict acknowledgement timing on the host, not FT1.2/cEMI. Not implemented. A GPIO
  TP-UART board was not commercially available.

## 13. References

- Weinzierl: [kBerry 838 datasheet](https://weinzierl.de/images/download/development/838/weinzierl-838-knx-baos-module-kberry-5208-datasheet-en.pdf),
  [product page](https://weinzierl.de/en/products/knx-baos-modul-838/),
  [KNX BAOS Starter Kit User's Guide](https://weinzierl.de/images/download/documents/baos/weinzierl_knx_baos_users_guide.pdf)
  (4.1.3 bus monitor, 4.6.1.7 cEMI server object, 5.2 cEMI, 5.4 FT1.2, 8.3/8.4 pins and
  dimensions, 13 Raspberry Pi), [BAOS SDK](https://github.com/weinzierl-engineering/baos)
- Raspberry Pi: [Configure UARTs](https://www.raspberrypi.com/documentation/computers/configuration.html#configure-uarts)
- KNX specification 03.06.03 EMI/IMI (cEMI message codes, communication mode), available via
  [my.knx.org](https://my.knx.org)
- knxd: [cEMI driver `cemi.cpp`](https://github.com/knxd/knxd/blob/main/src/libserver/cemi.cpp),
  [knxd#469](https://github.com/knxd/knxd/issues/469) (kBerry "reset timed out" reports)
- Calimero / openHAB: [calimero-core#116](https://github.com/calimero-project/calimero-core/issues/116)
  (PEI identify to detect cEMI), [calimero-server#24](https://github.com/calimero-project/calimero-server/issues/24)
  (Pi 5 report), [openhab-addons#13683](https://github.com/openhab/openhab-addons/issues/13683)
