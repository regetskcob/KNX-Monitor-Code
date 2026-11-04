# Changelog

## 1.9.7

- New: the KNX Monitor integration for Home Assistant, installed through HACS
  (<https://github.com/regetskcob/KNX-Monitor-HA>). With the add-on running, Home
  Assistant offers it as "New device found: KNX Monitor": sensors and recording
  switch as on the MQTT device, device triggers, the services "Create report" and
  "Export history", a diagnostics download and repairs when the bus has been gone
  for 10 minutes or the disk is full. No MQTT broker needed; while the integration
  is set up, the add-on no longer announces the same entities over MQTT.
- The integration gets its own token and only a few endpoints of the add-on
  (`/api/ha/`); everything else stays reachable through Ingress only.

## 1.9.6

- Connection "Home Assistant": the add-on now fills gaps in its history from the
  telegram store of the KNX integration (Home Assistant 2026.7 or newer). After the
  first start you see what Home Assistant already recorded, and telegrams from an
  update or restart of the add-on are no longer missing. It goes back at most as far
  as the history's retention; telegrams both have are taken only once.
- Exports › History as ETS file › "Everything": the whole history as a zip with one
  ETS file per day. SpectrumKNX imports it in one go. Also on the KNX Box.
- Charts: choose Loaded, Today, 7 or 30 days. The longer periods come from the
  history of the add-on or box, thinned on the server so peaks stay visible; periods
  the history does not reach yet are hidden. A click pins the crosshair and offers
  "Comment here" right there; across several days it also names the day. Dashed line
  ends are explained below the chart.
- Overview: every card whose value can be shown over time has its history again,
  switching states (windows, lights) as a step line. The histories repaint less often.
- Activity bar: hovering shows the time of the bar under the pointer.

## 1.9.5

- The history can be downloaded as an ETS group monitor file (Exports › Continuous,
  today, 7 or 30 days), the format of the ETS, Home Assistant's KNX telegram store and
  SpectrumKNX. Importing a recording now also reads files from Home Assistant /
  knx-telegram-store, SpectrumKNX, ETS 6, Gira loggers and Node-RED knx-ultimate.
- The MQTT device "KNX Monitor" has new key figures for dashboards and automations:
  bus load in %, open alarms, last alarm (name and time), availability over the last
  24 hours, history size, free space and a low-space flag. New device triggers fire
  when the bus connection is lost or back. Existing entities stay as they are.
- New blueprints: "Bus load high" and "Recording space low".
- Under the hood: the KNX protocol code of app and add-on (addresses, cEMI, datapoint
  types, KNX Secure) now lives in one shared package instead of two copies.

## 1.9.4

- KNX Monitor is now open source under GPLv3:
  <https://github.com/regetskcob/KNX-Monitor-Code>. Everything the server sends to the bus
  passes one file there (`ha-addon/knx_monitor/server/lib/src/read_only.dart`).
- New option `read_only`, on by default: the server sends nothing to the bus, neither
  from the app nor through its relay, not even read requests. Recording and evaluations
  keep running. Turn it off in the add-on configuration to write or request values.
  Docker and the KNX Box get the same with `READ_ONLY=1` (off by default there).
- Dark mode: outlines have a little more contrast.
- Packing a finished history day survives a power cut without losing or duplicating
  telegrams.

KNX Box, with its next image:

- The setup also prepares the serial port for the kBerry on a Raspberry Pi 3 (not yet
  tested on hardware), and USB serial adapters are allowed as bus interface.
- With LAN access off, the box refuses every new connection over the cable (also SSH and
  the Prometheus export), not only the web app.
- kBerry: a telegram that nobody on the bus acknowledged is reported as failed.

## 1.9.3

- New interface: a green status box above overview, details and live, cards in a grid,
  a write button in the header and a live list that leads with the address and name.
- The menu is sorted by task, with icons, and evaluations now stand on their own.
- The communication map shows devices in layers and zoom levels. A device without
  links is marked in the full map.
- Topology and project check open faster, device drawings appear one by one.
- The Home Assistant configuration now lives only here in the add-on, not in the apps.

## 1.9.2

Add-on, KNX box and Docker:

- A malformed frame from a client or a forged gateway packet can no longer stop the
  server.
- Reports and data export no longer send to link-local or cloud metadata addresses.
- Recording checks the free disk space. When it gets tight the oldest days go first
  (today stays); if that is not enough, recording pauses and the app says so. It
  resumes by itself. History is now forced to disk every 30 seconds instead of every
  5, which is easier on SD cards: a power cut can cost up to 30 seconds.

KNX box and Docker:

- Devices paired through the QR code on `/pair` can read and send group values, but
  no longer read the keyring, change the bus connection, project or history, restart
  or program devices. Devices paired with the box password keep all rights.
- Revoking a device or changing the password closes its open connections at once.
- A device token no longer resets failed password attempts, and non-admin devices can
  no longer test a guessed Secure password.
- The health check `/healthz` answers without a login and without any data.
- Password checks are limited per address, so many parallel attempts cannot slow down
  the box.
- HTTPS with your own certificate (`TLS_CERT`, `TLS_KEY`, `TLS_PORT`).
- Docker: the template now uses a fixed version and answers only on the host by
  default; set `LAN_ACCESS=yes` for your network.
- Images and box files are signed (cosign), box releases carry checksums.

KNX box:

- A new box asks for your own password first; the one on the sticker only pairs and
  changes the password. Afterwards it disappears from the SD card, as does the Wi-Fi
  password once you change it in the app (new). Updated boxes are asked, not locked.
- Forgot a password: put `knx-box-reset.txt` on the SD card and restart.
- HTTPS with the box's own certificate; newly paired apps verify exactly this
  certificate. Apps paired earlier keep working over HTTP until you pair them again.
- The system log is limited to 64 MB.

## 1.9.1

- Recording without a known clock stays visible as "without time" after a
  restart and is removed by the retention like any other day.
- A day is no longer overwritten when the clock jumped while it was being
  packed.
- Project and keyring are checked when the app reconnects to a box.
- Checking the box password no longer blocks the server and the recording.
- Stopping no longer hangs on an unresponsive KNX HAT and is no longer counted as
  an unexpected restart.

## 1.9.0

- Beginners: teach in your installation without an ETS project; without
  expert mode the live list shows every telegram as a sentence.
- New: connection help, a status light with weekly report and "Learn KNX".
- Cause chain and reaction times, in plain sentences without expert mode.
- Home Assistant: the generated KNX configuration can now suggest devices.
  Plus a security check, a device inventory and a forum package.
- Project check with new rules (multiple read responses, addresses without
  sender or receiver, crowded lines, unfiltered main groups 14/15, missing
  names or types, central off/on) and "Tasks for ETS" as list, PDF and ETS
  import (preview).
- Electricians: ring-through with sound acknowledgement, signed acceptance
  report, and a fault hunt that catches sporadic faults over days.
- Dashboard chart cards with templates and bus figures.
- Neutral front view for actuators without a manufacturer graphic.
- Resilience: settings and installation files are restored from backups if
  damaged; the KNX box rolls back an update that does not start.
- Connecting to another gateway switches the continuous recording and fault
  hunt only once the new connection works; a failed attempt keeps the old one.
  The connection help now appears in the add-on too.

## 1.8.4

- Nothing changes for Home Assistant users.
- KNX box (preview): the box can now connect to the KNX line directly through
  the Weinzierl kBerry plug-on module, without a KNX/IP gateway. Choose
  "KNX-HAT (kBerry)" as the connection mode (expert mode); a bus monitor mode
  with acknowledgements is available too.
- KNX box: the browser no longer asks for the password again on every
  "Connect", and the monitor now opens in Safari and on iPad/iPhone. Any user
  name works when signing in, only the box password counts.
- KNX box: the box now starts without a USB SSD (data then stays on the SD
  card), and with an SSH key set, the maintenance account can use sudo.
- KNX box: connection texts on the box say "Box" instead of "Add-on".

## 1.8.3

- New introduction on the connect screen: three chapters (basics,
  analysis, expert mode) with real views in the demo house. In the add-on and
  on the KNX box all three run in one go, and the last card opens the demo
  house. The button stands out as long as a chapter is unseen.
- Device sheet: the action buttons no longer wrap on narrow phones; they sit
  side by side while they fit, otherwise one below the other.
- KNX box (preview): the printable case is now a single slim variant for
  Pi 3B to 5 with the kBerry, with a module bridge, a USB cover, an
  optional base for DIN rails and test prints for the heat-set inserts and
  the lid. Print it at 0.2 mm layer height.

## 1.8.2

- Nothing changes for Home Assistant users.
- KNX box (preview): prepared for a direct connection to the KNX line with the
  Weinzierl KNX BAOS 838 kBerry plug-on module for the Raspberry Pi. The
  image frees the serial port for the module, and the box settings in the app
  can test it: response, supported modes, telegrams and a bus monitor with
  acknowledgements. Recording keeps running over IP for now.
- The box page has a guide for tinkerers and a printable case with a variant
  for the kBerry (both previews, not yet tested on real hardware).

## 1.8.1

- Nothing changes for Home Assistant users.
- KNX Monitor also runs as a Docker container without Home Assistant (for
  example next to ioBroker, on a NAS or Proxmox): one image for amd64 and
  arm64, `ghcr.io/regetskcob/knx-monitor`, with a password and optionally
  MQTT. Instructions in the repository under `docker/`.
- MQTT: every value is also published as its own topic, and the broker can be
  set through environment variables outside Home Assistant.

## 1.8.0

- Automations: the add-on fires the events `knx_monitor_watcher`,
  `knx_monitor_alarm` and `knx_monitor_bus`, also without an open browser.
  Three blueprints to import with one click are linked in the documentation.
- With an MQTT broker (Mosquitto) the add-on appears as the device
  "KNX Monitor": bus connected, recording switch, telegrams per minute and
  today, repeats, last telegram, event entities and device triggers for each
  watcher and for alarms and faults.
- New options `alarm_notifications` and `watcher_notifications`: turn the
  notifications off if you notify through your own automations.
- If the KNX integration is set up, the add-on suggests sharing its
  connection instead of taking an own tunnel slot.
- The menu shows the version of the app and the add-on; diagnostics packages
  include the add-on version, screen size and time zone.

## 1.7.9

- After a dropped connection, for example while the Home Assistant app was in
  the background, the view fetches the missed telegrams from the recording
  instead of continuing right after the old ones.
- Activity bar "today": the rest of the day is a plain line instead of
  looking like a gap in the recording.
- Details: the history shows the latest 40 values; full screen shows all of
  them and scrolls.
- KNX box built from this version: the same fixes.

## 1.7.8

- Fixed: the add-on page stayed blank since 1.7.1. It starts again.
- Statistics: load peaks and heatmap cells filter the monitor by time (new
  filter term `time:`, e.g. `time:14:05-14:10`); in English, sender filters
  use `from:`.
- Health check shows its progress while reading and the expected duration
  next to "Check now".
- Overview without an ETS project: guessed date and time values are shown
  large, the raw bytes small below.
- Long values in the history wrap instead of running out of the details.
- KNX box built from this version: the same fixes, its web page starts again.

## 1.7.7

- Nothing changes in Home Assistant.
- KNX box built from this version: the printable sheet has two labels of the
  same size, label 1 for the app on top of the box and label 2 with the
  Wi-Fi on the bottom.

## 1.7.6

- Nothing changes in Home Assistant.
- KNX box built from this version: after the first start the SD card holds
  one printable sheet per language (knx-box-de.pdf, knx-box-en.pdf) with the
  label to cut out, Wi-Fi code, passwords, the link for the Linux app and the
  next steps.

## 1.7.5

- Comments on telegrams, charts and recordings, with up to three
  screenshots each. Telegram lists flag commented addresses; all comments are
  listed under Tools › Comments.
- Timeline for recordings: one lane per group address, drag and zoom, tap a
  telegram to comment on it.
- "Report a problem": start, reproduce the fault, tap "It happened now" each
  time, then send the diagnostic package to your electrician.
- Opening a diagnostic package shows findings: the problem with screenshots,
  automatic hints (connection, Secure, repeats, unanswered reads, outages),
  comments and the busiest addresses.
- One page for all exports: telegrams as PDF, CSV or ETS file, reports (bus
  statistics, health check, commissioning log), a combined ZIP and the last
  exports to share again.
- PDFs are built in the background and break long tables across pages;
  large health reports no longer freeze the app.
- KNX box built from this version: reachable only in its own Wi-Fi by
  default; access over the network cable can be turned on in the app.

## 1.7.3

- The add-on links to its website knx-monitor.de, with support, privacy
  policy and FAQ.

## 1.7.2

- Actuators of all manufacturers use the app's own drawing again. Device
  graphics that were only meant for testing are no longer included.

## 1.7.1

- Topology and device, coupler and actuator details use far less CPU in the
  add-on: no animations, drawings refresh at most once per second.
- Diagnostic package contains the whole session instead of the last 5000
  telegrams shown, and can use days from the long-term history as source.
- Chart tiles show values over time like the full-screen chart, on/off values
  as narrow bands.
- Dialogs, favourites and pins look clearer; the web app starts in the colours
  of the splash screen.

## 1.7.0

- Watchers run in the add-on: they keep working without an open browser and
  send a Home Assistant notification (also as push with `notify_service`).
  Watchers are stored in the add-on and shared by all browsers.
- Bus monitor works next to the add-on: the add-on hands its tunnel over while
  the bus monitor is open (before, the gateway reported no free tunnels).
- Switching away from the KNX Monitor panel and back keeps the last values and
  telegrams instead of starting empty.
- ETS project import shows its progress and opens password-protected ETS5
  projects faster.
- Topology stays smooth with long recordings.
- Charts: on/off values get a row of their own; charts can be prepared with
  project addresses that have not sent yet; "free selection" is gone.
- Project check uses two columns on wider screens.
- Sidebar starts with the overview.

## 1.6.0

- Topology: lines, couplers and devices as a tree with a detail area; line
  couplers, power supplies, actuators, push buttons, presence detectors,
  weather stations and smoke detectors are drawn like the real devices, with
  status LEDs and telegram pulses on the bus cable.
- Switching objects can be sent as 0/1 directly from the object list and the
  topology.
- Project import reads the flags of the communication objects (C R W T U);
  the project check compares the ETS project without any bus traffic.
- Group objects of ETS modules get the right object numbers.
- Import your ETS project once more to see the flags and the corrected
  object numbers.
- Values without a project: 3- and 8-byte values are shown as date and time.
- Bus monitor on narrow screens: value below the destination, full raw data,
  tap a sender to filter the list.
- Very wide screens show the live list as a column next to the overview.
- Diagnostics package for support: error report, recording, project and
  technical details as a ZIP, without personal data.
- Data is now stored per installation; existing data moves into the first
  installation automatically at start.

## 1.5.1

- Security: the add-on's own files – the bus connection with the IP Secure
  passwords and the access data of the KNX box – are no longer reachable
  through the add-on's file store. Projects, recordings and history are
  unaffected.

## 1.5.0

- New look: KNX Monitor now uses Horizont, the design system it shares with
  the other regetskcob projects. Inside Home Assistant the add-on takes Home
  Assistant's neutral colours, so it sits calmly in its frame; the green
  accent, the type and the lines stay.
- New icon: a bus terminal on the green bus cable.
- Values, addresses and times are set in a monospaced font; every status
  shows a glyph and a word, not just a colour.
- Telegram types are letters on a tint: W in the accent, R amber, A blue.
- From 600 px the menu is a sidebar on the left that can be shown and hidden.
- Recordings: a long press on record keeps the last 10 seconds; before a
  replay you can change values, remove telegrams and save the edit as a copy.
- Charts are saved per installation and show up as their own section on the
  overview; addresses are picked like on the dashboard.
- Expert mode (on by default in the add-on) gathers the workshop tools and
  can replay a recording onto the bus after an explicit confirmation; the
  live list shows the hop count for each telegram.
- Search sits in the title bar, the quick filters are one Filter button
  with counts, and the commissioning filters fit in one row.

## 1.4.0

- Quick filters such as "Unanswered" now also work in the overview and
  objects: an address matches if any of its telegrams does.
- Room numbers such as "OG K1" in ETS names are recognised, so objects are
  grouped by the right room.
- Dialogs now match the look of the rest of the app.
- The "Newest" marker stays visible while scrolling.
- More robust saving: catalogue, commissioning and settings are written
  safely, so an interrupted write no longer leaves an empty file.

## 1.3.0

- New: continuous recording. The add-on keeps one bus connection open on its
  own (also without an open browser), reconnects immediately after dropouts
  and writes the history itself. All open views share this one tunnel.
- New: connection types UDP or TCP tunnel, fixed tunnel address with
  fallback, KNXnet/IP routing, KNX IP Secure, and a Home Assistant mode that
  reads the telegrams of the KNX integration without its own tunnel.
- New: KNX Data Secure – import the ETS keyring; secured telegrams are
  decrypted live and in the recording.
- History: finished days are compressed, size limit, write interval,
  availability log that explains gaps (bus disconnected vs. add-on not running).
- Alarm notifications now come from the add-on itself, also without a browser.
- Long-term statistics: activity heatmap, busiest addresses and senders.
- Expert mode is on by default in the add-on.

## 1.2.0

- New: "Health" tool – reads known status addresses, reports newly silent
  addresses, cycle watchdog, plausibility, DPT check per sender, bus quality.
- New: commissioning checklist with notes and PDF report.
- The communication map starts with an overview of all addresses and devices.
- Senders/receivers from the ETS project based on communication flags,
  tunnel addresses shown separately in the topology.
- Thousands separators, kW/kWh, average values and step lines in the overview.
- Prebuilt images for amd64 and aarch64.

## 1.1.0

- Alarm notifications via Home Assistant, bus monitor, topology.

## 1.0.0

- Initial release.
