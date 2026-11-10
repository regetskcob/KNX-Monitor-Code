---
title: "Changelog"
description: "What the latest versions of Busclear brought to the app, the Home Assistant add-on and the Busclear Box, newest first."
layout: "page"
slug: "changelog"
---
What the latest versions of Busclear brought, newest first. App, Home Assistant add-on and Busclear Box share one version number. Every version is on [GitHub](https://github.com/regetskcob/KNX-Monitor/releases); in Home Assistant the add-on shows the same notes before an update.

## 1.11.0 – 10 Nov 2026

- Fewer false "stopped sending" alerts: group addresses that send in bursts (dimming, blinds while moving, switching with status feedback) no longer count as cyclic. This affects the repair in the Home Assistant integration and the app's health check.
- New card "Last 7 days" in the overview (add-on and Busclear Box): telegrams per day, bus load, repeats, how long the recording ran, and what is worth a look, such as several clocks, read storms, very chatty addresses, silent devices, unknown senders and dropped connections.
- Project against bus: with the add-on or the box the project check also uses the recording. It names devices that send where the project says they do not, commands whose status never answers, unanswered read requests, contacts and alarms stuck at 1 for days, and presence detectors that trigger most nights. For addresses without a datapoint type it suggests one. New without a recording too: devices never programmed, or not since the last change.
- XKNX Editor: Busclear opens projects of the [XKNX Editor](https://github.com/XKNX/xknx-editor) (`.xknx`), also password-protected ones. In the add-on, "From Home Assistant" takes over the project of the KNX integration. Findings go to the editor as corrections and comments, and a device can be compared with the project, read only. Nothing is programmed.
- AI access (MCP): AI tools such as Claude can read the recording, device activity, findings and the project check. Read only, off by default, with its own token; switch it on under Exports › Continuous › AI access (MCP).
- Tap points ([#8](https://github.com/regetskcob/KNX-Monitor/issues/8)): a connected tap point that hears nothing is reported. The time window for merging measures itself. When a tap point was gone, the recordings show a gap instead of a bus fault. The telegram list filters by tap point or by "seen at one tap point only", and with tap points on several lines the topology checks the couplers' filter tables against the project. The origin is the tap point on the sender's line (highest hop count), not the fastest one: a kBerry reports about 40 ms after a KNX IP interface. And the evaluations in the background no longer hold up the bus for a moment, so telegrams are no longer listed twice.
- Bus load in percent as a key figure and chart template, also on the dashboard card. Connection drops go to the availability log at once with their reason, also when the connection comes back within a minute.
- MQTT ([#11](https://github.com/regetskcob/KNX-Monitor/issues/11)): with the option "Keep last value per address" (Docker and box: `MQTT_RETAIN_VALUES=true`) each new value also goes to `knx_monitor/value/1/2/3`, retained. Whoever subscribes later gets the current state at once. The guide has a Node-RED example.
- Home Assistant integration 1.2.0 ([#12](https://github.com/regetskcob/KNX-Monitor/issues/12)): if a Busclear Box or container no longer accepts the key, Home Assistant asks for a new pairing link instead of only failing.
- Docker: with `PUID`/`PGID` the server runs without root rights; the template sets 1000:1000.
- Lessons: "Try it" goes straight to the place in the app the lesson talks about. On the Mac, sharing first asks "Save As…" or "Share…".
- Several Busclear Boxes with one app: every installation and every box now has its own identifier. Two boxes whose installation has the same name stay two separate installations in the app, and an installation stays the same when it is passed on in a handover package. The identifier grants no access.
- The KNX protocol now comes from the open packages [knx](https://pub.dev/packages/knx) and [knx_io](https://pub.dev/packages/knx_io).

## 1.10.0 – 8 Nov 2026

- KNX Monitor is now **Busclear**, the KNX box is now the **Busclear Box**. Same add-on, same features: projects, recordings, settings and automations stay. Existing entities keep their IDs (`knx_monitor_…`), add-on slug and MQTT topics stay, the box keeps its Wi-Fi `KNX-Box-…`. The website is now busclear.de (knx-monitor.de redirects), support via support@busclear.de.
- Tap points ([#8](https://github.com/regetskcob/KNX-Monitor/issues/8)): up to eight connections per installation, e.g. one interface per line, merged into one history. Each telegram keeps where it was seen first and the other sightings with offset and hops. The app shows the lines as chips, reports a dropped tap point and shows the path through the installation in the telegram details.
- Every telegram to MQTT, traceable and with raw data ([#11](https://github.com/regetskcob/KNX-Monitor/issues/11)): running number, server start, installation id, time in microseconds, hops, device name of the sender and project state. New: send raw data too, raw data only, and a filter on group addresses.
- Docker guide: the telegram stream variables are in the table; every release test-starts the published `compose.yaml` and the `docker run` example.

## 1.9.10 – 7 Nov 2026

- Preview for testers: every telegram to MQTT ([#11](https://github.com/regetskcob/KNX-Monitor/issues/11)). With the new add-on option "Every telegram to MQTT" (Docker and box: `MQTT_TELEGRAMS=true`) each group telegram goes as JSON to `knx_monitor/telegram/1/2/3`, with time, name, DPT, value and unit from the ETS project. Off by default. KNX Secure telegrams only with a separate option, at most 500 per second. Feedback in the issue, please.
- Home Assistant integration 1.1.0 ([#2](https://github.com/regetskcob/KNX-Monitor/issues/2)): event entities, a device trigger per watcher, conditions (bus connected, recording on, alarm open, low space) and a repair when a group address that usually sends regularly goes silent. Without Supervisor (Home Assistant Container) it connects to a KNX box or Docker through a pairing link with "Manage".
- The KNX box survives power cuts more cleanly ([#4](https://github.com/regetskcob/KNX-Monitor/issues/4)): without a real-time clock the clock starts from the last saved stamp instead of the date of the first boot, and until then nothing is packed or deleted by age. The system journal is kept, and the restart list names the reason.
- After a crash the app shows a notice and leads to the diagnostics package; "Report as issue" opens a prefilled form with only version, platform, time and kind of crash.
- KNX box: in the box settings, "Raspberry Pi" shows the temperature, its maximum since start and warnings for under-voltage or throttling.
- KNX HAT (kBerry): the bus monitor now counts frames the module saw but did not pass on, and the app explains it: the kBerry leaves out about every second data frame in bus monitor mode, so the box records completely in link layer mode. Recovery after a module restart and 115200 baud were tested on a real line.
- Security review for Docker: the UDP relay forwards only KNXnet/IP to gateway addresses, without `LAN_ACCESS` the container listens on localhost only (a reverse proxy on the same host needs `LAN_ACCESS=yes`), admin access is granted only with the password, "lock out all" also ends browser sessions, the first password needs 8 characters (`BOX_PASSWORD_FILE` for Docker secrets), and paired devices can no longer delete history or stall the server. The Docker template now starts read only (`READ_ONLY=0` to send) and uses HTTPS on port 8443. Details in the Docker README.
- KNX box and Docker: own login page in the browser with the password only, instead of the browser's dialog that also asked for a user name that did not matter. "Abmelden" (log out) on the pairing page ends the session, and the web app returns to the login page when the session has run out. Apps and tools such as curl log in as before.
- Hints in a telegram's detail sheet, findings, security notes, address, name and product in the device sheet and the details for an issue report can be selected and copied, for example for a question in a forum.

## 1.9.9 – 6 Nov 2026

- Docker: `LAN_ACCESS` now applies on every start. Setting `LAN_ACCESS=yes` later used to have no effect. Messages, the login dialog and the settings page speak of network access and the password instead of the box Wi-Fi, which does not exist in Docker.
- Alarms on the add-on and the KNX box use the names you corrected or taught in the app.
- The Home Assistant notification for findings says in plain words what is wrong and leads to the add-on page.
- Diagnostic and handover packages keep corrected group address names, so the tasks for the ETS survive.
- Topology: devices with an address outside the project, such as the KNX module of a box on the factory address 15.15.255, appear on the gateway's line with a hint, instead of as an extra line with a missing coupler.

## 1.9.8 – 5 Nov 2026

- Security and speed: this version follows a thorough review of all parts, a penetration test and a load test with 30 days of 100,000 telegrams each.
- Charts over 7 and 30 days and the statistics answer much faster, also with several viewers at once. The web app loads smaller and comes from the cache the second time.
- Setting the history to "Off" deletes it: the app now asks first.
- KNX Box and Docker: the box password can only be changed with the current one. Pairing offers the level "View only", which sends nothing to the bus. Paired devices only see the active installation.
- Pairing links from outside show the address and warn about unencrypted connections. A box that is already paired is only replaced after asking.
- Group address names can be corrected in the app and returned to the ETS as an import file.
- CSV exports open cleanly in Excel, with umlauts, negative numbers and times with time zone. Error messages are clearer, deleting asks first or can be undone.
- Home Assistant integration 1.0.2: its services are available to administrators only.

## 1.9.7 – 4 Nov 2026

- New for Home Assistant: the "KNX Monitor" integration through HACS ([KNX-Monitor-HA](https://github.com/regetskcob/KNX-Monitor-HA)). With the add-on running, Home Assistant shows "New device found". You then get sensors and the recording switch as on the MQTT device, device triggers for watchers, alarms and the bus connection, the services "Create report" and "Export history", a diagnostics download and repairs when the bus has been gone for a while or the disk is full. No MQTT broker needed.

## 1.9.6 – 4 Nov 2026

- Charts: besides "Loaded" there are now "Today", "7 days" and "30 days" from the continuous recording of the add-on and KNX Box. A click sets the crosshair and offers "Comment here" right there; the comment keeps the previous and current value of every line.
- Overview: every card with a value history shows it again, switching states such as windows and lights as blocks for "on". Histories repaint less often.
- Hovering the activity bar shows the time of the bar. The cause chain names when the telegram arrived.
- Comments open as a proper dialog on iPad, Mac and in the browser instead of a narrow alert.
- Home Assistant add-on: when connected through the KNX integration, the add-on fills gaps from its telegram store (Home Assistant 2026.7 or newer). Right after installing you see what Home Assistant already recorded, and an update no longer leaves a hole.
- The whole history can be exported as a zip with one ETS file per day; SpectrumKNX imports it in one go. Also on the KNX Box.

## 1.9.5 – 3 Nov 2026

- The history of the add-on and KNX Box can be downloaded as an ETS group monitor file, the format Home Assistant's telegram store and SpectrumKNX use too.
- Importing recordings now also reads files from Home Assistant, SpectrumKNX, ETS 6, Gira loggers and Node-RED knx-ultimate.
- Home Assistant: the MQTT device "KNX Monitor" reports bus load, open alarms, availability over the last 24 hours and free space, plus two new blueprints.

## 1.9.4 – 3 Nov 2026

- KNX Monitor is open source under the GPLv3: [KNX-Monitor-Code](https://github.com/regetskcob/KNX-Monitor-Code). Everything the server sends to the bus passes one single file.
- New "read only" option in the add-on, on by default: the server sends nothing to the bus, not even read requests. Recording and evaluation keep running. Docker and the KNX Box have the same as a switch.
- Outlines have a little more contrast in dark mode.

## 1.9.3 – 2 Nov 2026

- New interface: a green status box above overview, details and live, cards in a grid, a write button at the top and a live list that leads with address and name.
- The menu is sorted by task, with icons; evaluations stand on their own.
- The communication map shows devices in layers and zoom levels; topology and project check open faster.
- Accounts are gone for now: the app no longer signs in and talks to no account service. Your data on the device stays as it is.

## 1.9.2 – 1 Nov 2026

- New for anyone planning or building: the home plan, no gateway needed, in the Home Assistant add-on, in the KNX Box browser and in the Linux app. You go through your everyday life, and that becomes a room book and floor plan for talking to your contractor. You set lights and sockets as switchable, dimmable or permanently powered; the app works out the channel demand and exports the device list as CSV and PDF. It also covers all levels including the outdoor area, checks such as a button inside a door swing, deadlines per construction type, offer check, PDF with dimensions and DXF. The catalog is compiled to the best of our knowledge and does not replace electrical planning.
- Before writing to the bus, a notice says that this is an intervention in the installation. You can hide it and turn it back on from the start page; hiding it is recorded with the date in the diagnostics package.
- Security in the apps: pairing links warn about unknown addresses, backups no longer contain purchase keys, encryption is about ten times faster.
- KNX Box and add-on: HTTPS, mandatory change of the sticker password, separate roles and more protection against broken telegrams and full disks.
- Handling: On phones the search makes room, the keyboard fits the field and closes when you scroll. On Mac, Windows and iPad with a keyboard there are shortcuts and a right-click menu on telegrams.

## 1.9.1 – 31 Oct 2026

- Your data: the apps now encrypt their files with AES-256-GCM, with the key in the system keychain. Without a usable keychain (Linux without libsecret) they stay unencrypted, as do settings such as the gateway.
- Optional app lock: Face ID, fingerprint, Windows Hello, device code or an app password plus recovery key as PDF.
- Backup: everything from this device in one file with its own password, in the apps, in an openly described format.
- Diagnostics package: screenshots only go along if you turn them on.
- Photos of the distribution board and labels with QR codes, per installation.
- Account (optional): two-factor sign-in, export of account data, a removed device loses its session on the server.
- KNX box and add-on: a recording without a known clock stays visible after a restart and is removed by the retention like any other day. A day is no longer overwritten when the clock jumps while it is being packed. Project and keyring are checked on reconnecting. Checking the password no longer holds up the server and the recording. Stopping no longer hangs on an unresponsive KNX HAT.

## 1.9.0 – 29 Oct 2026

- For beginners: you can now teach in your installation without any ETS project – press a button, name it, done; the app builds a project of its own from it. Without expert mode the live list shows every telegram as a sentence ("Hallway button switched on kitchen light").
- New: connection help that explains step by step why the gateway does not answer; a status light on the home screen with a weekly report; "Learn KNX" with short lessons.
- Cause chain and reaction times: what a telegram triggered and how fast the feedback came, without expert mode in the same sentences as the live list.
- Home Assistant: the generated KNX configuration can now suggest devices too. Plus a security check, a device inventory (manufacturer, serial number, firmware) and a forum package with everything needed for a question in a forum.
- Project check with new rules: multiple read responses, addresses without sender or receiver, crowded lines, unfiltered main groups 14/15, addresses without name or datapoint type, and central off/on. "Tasks for ETS" collects everything as a list and PDF, the group addresses also as an ETS import (preview).
- For electricians: ring-through with sound acknowledgement (every button confirms audibly, with a test tone first), an acceptance report signed on the device, and a fault hunt that catches sporadic faults over days with the KNX box.
- Dashboard: chart cards with templates and bus figures; templates can be shared.
- Actuators without a manufacturer graphic now get a neutral front view with channels, label fields and bus terminal.
- Resilience: the app starts even with damaged settings or installation files and restores them from backups. The KNX box keeps the previous version on update and rolls back if the new one does not start.
- Home Assistant add-on and KNX box: connecting to another gateway switches the continuous recording and fault hunt only once the new connection works. The connection help now appears there too.
- KNX box (preview): DIN rail base with a screw-on spring clip; variant 1 is recommended.

## 1.8.4 – 26 Oct 2026

- KNX box (preview): the box can now connect to the KNX line directly through the Weinzierl kBerry plug-on module, without a KNX/IP gateway. Choose “KNX-HAT (kBerry)” as the connection mode (expert mode); a bus monitor mode with acknowledgements is available too.
- KNX box: the browser no longer asks for the password again on every “Connect”, and the monitor now opens in Safari and on iPad and iPhone. Any user name works when signing in, only the box password counts.
- KNX box: the box now starts without a USB SSD (data then stays on the SD card), and with an SSH key set, the maintenance account can use sudo.
- KNX box: connection texts on the box say “Box” instead of “Add-on”.

## 1.8.3 – 25 Oct 2026

- New introduction on the connect screen: three chapters (basics, analysis, expert mode) with real views in the demo house. In the add-on and on the KNX box all three run in one go, and the last card opens the demo house. The button stands out as long as a chapter is unseen.
- Device sheet: the action buttons no longer wrap on narrow phones; they sit side by side while they fit, otherwise one below the other.
- KNX box (preview): the printable case is now a single slim variant for Pi 3B to 5 with the kBerry, with a module bridge, a USB cover, an optional base for DIN rails and test prints for the heat-set inserts and the lid. Print it at 0.2 mm layer height.

## 1.8.2 – 25 Oct 2026

- KNX box (preview): prepared for a direct connection to the KNX line with the Weinzierl KNX BAOS 838 kBerry plug-on module for the Raspberry Pi. The image frees the serial port for the module, and the box settings in the app can test it: response, supported modes, telegrams and a bus monitor with acknowledgements. Recording keeps running over IP for now.
- The box page has a guide for tinkerers and a printable case with a variant for the kBerry (both previews, not yet tested on real hardware).

## 1.8.1 – 25 Oct 2026

- KNX Monitor also runs as a Docker container without Home Assistant (for example next to ioBroker, on a NAS or Proxmox): one image for amd64 and arm64, `ghcr.io/regetskcob/knx-monitor`, with a password and optionally MQTT.
- MQTT: every value is also published as its own topic, and the broker can be set through environment variables outside Home Assistant.

## 1.8.0 – 25 Oct 2026

- Automations: the add-on fires the events `knx_monitor_watcher`, `knx_monitor_alarm` and `knx_monitor_bus`, also without an open browser. Three blueprints to import with one click are linked in the documentation.
- With an MQTT broker (Mosquitto) the add-on appears as the device “KNX Monitor”: bus connected, recording switch, telegrams per minute and today, repeats, last telegram, event entities and device triggers for each watcher and for alarms and faults.
- New options `alarm_notifications` and `watcher_notifications`: turn the notifications off if you notify through your own automations.
- If the KNX integration is set up, the add-on suggests sharing its connection instead of taking a tunnel slot of its own.
- The menu shows the version of the app and the add-on; diagnostic packages include the add-on version, screen size and time zone.

## 1.7.9 – 24 Oct 2026

- After a dropped connection, for example while the Home Assistant app was in the background, the view fetches the missed telegrams from the recording instead of continuing right after the old ones.
- Activity bar “today”: the rest of the day is a plain line instead of looking like a gap in the recording.
- Details: the history shows the latest 40 values; full screen shows all of them and scrolls.

## 1.7.8 – 23 Oct 2026

- Fixed: the add-on page stayed blank since 1.7.1. It starts again, and so does the web page of the KNX box.
- Statistics: load peaks and heatmap cells filter the monitor by time (new filter term `time:`, e.g. `time:14:05-14:10`); in English, sender filters use `from:`.
- Health check shows its progress while reading and the expected duration next to “Check now”.
- Overview without an ETS project: guessed date and time values are shown large, the raw bytes small below.
- Long values in the history wrap instead of running out of the details.

## 1.7.7 – 23 Oct 2026

- KNX box: the printable sheet has two labels of the same size, label 1 for the app on top of the box and label 2 with the Wi-Fi on the bottom.

## 1.7.6 – 23 Oct 2026

- KNX box: after the first start the SD card holds one printable sheet per language with the label to cut out, Wi-Fi code, passwords, the link for the Linux app and the next steps.

## 1.7.5 – 23 Oct 2026

- Comments on telegrams, charts and recordings, with up to three screenshots each. Telegram lists flag commented addresses; all comments are listed under Tools › Comments.
- Timeline for recordings: one lane per group address, drag and zoom, tap a telegram to comment on it.
- “Report a problem”: start, reproduce the fault, tap “It happened now” each time, then send the diagnostic package to your electrician.
- Opening a diagnostic package shows findings: the problem with screenshots, automatic hints (connection, Secure, repeats, unanswered reads, outages), comments and the busiest addresses.
- One page for all exports: telegrams as PDF, CSV or ETS file, reports (bus statistics, health check, commissioning log), a combined ZIP and the last exports to share again.
- PDFs are built in the background and break long tables across pages; large health reports no longer freeze the app.
- KNX box: reachable only in its own Wi-Fi by default; access over the network cable can be turned on in the app.

## 1.7.3 – 22 Oct 2026

- The add-on links to its website knx-monitor.de, with support, privacy policy and FAQ.

## 1.7.2 – 22 Oct 2026

- Actuators of all manufacturers use the app’s own drawing again. Device graphics that were only meant for testing are no longer included.

## 1.7.1 – 22 Oct 2026

- Topology and device, coupler and actuator details use far less CPU in the add-on: no animations, drawings refresh at most once per second.
- The diagnostic package contains the whole session instead of the last 5,000 telegrams shown, and can use days from the long-term history as source.
- Chart tiles show values over time like the full-screen chart, on/off values as narrow bands.
- Dialogs, favourites and pins look clearer; the web app starts in the colours of the splash screen.

## 1.7.0 – 21 Oct 2026

- Watchers run in the add-on: they keep working without an open browser and send a Home Assistant notification (also as push with `notify_service`). Watchers are stored in the add-on and shared by all browsers.
- The bus monitor works next to the add-on: the add-on hands its tunnel over while the bus monitor is open (before, the gateway reported no free tunnels).
- Switching away from the KNX Monitor panel and back keeps the last values and telegrams instead of starting empty.
- ETS project import shows its progress and opens password-protected ETS5 projects faster.
- Topology stays smooth with long recordings.
- Charts: on/off values get a row of their own; charts can be prepared with project addresses that have not sent yet; “free selection” is gone.
- The project check uses two columns on wider screens.
- The sidebar starts with the overview.

## 1.6.0 – 21 Oct 2026

- Topology: lines, couplers and devices as a tree with a detail area. Line couplers, power supplies, actuators, push buttons, presence detectors, weather stations and smoke detectors are drawn like the real devices, with status LEDs and telegram pulses on the bus cable.
- Switching objects can be sent as 0/1 right from the object list and the topology.
- The project import reads the flags of the communication objects (C R W T U); the project check compares the ETS project even without any bus traffic.
- Values without a project: 3- and 8-byte values are shown as date and time.
- Diagnostics package for support: error report, recording, project and technical details as a zip, without personal data.
- Data is now kept per installation; existing data moves into the first installation at start.

## 1.5.1 – 19 Oct 2026

- Add-on security: the bus connection with the IP Secure passwords and the access data of the KNX Box are no longer reachable through the add-on's file store.

## 1.5.0 – 19 Oct 2026

- New look with Horizont, the design system shared by all my projects. Inside Home Assistant the add-on takes Home Assistant's neutral colours; accent, type and lines stay.
- New icon: a bus terminal on the green bus cable.
- Values, addresses and times in a monospaced font; every status shows a glyph and a word, not just a colour.
- Recordings: a long press on record keeps the last 10 seconds. Before a replay you can change values and remove telegrams.
- Charts are saved per installation and show up as their own section on the overview.
- From 600 px the menu is a sidebar.

## 1.4.0 – 18 Oct 2026

- Quick filters such as "Unanswered" now also work in the overview and objects.
- Room numbers such as "OG K1" in ETS names are recognised, so objects land in the right room.
- Safer saving: an interrupted write no longer leaves an empty file.

## 1.3.0 – 17 Oct 2026

- New in the add-on: continuous recording. The add-on keeps its own bus connection open, also without an open browser, reconnects right after dropouts and writes the history. All open views share this one tunnel.
- Connection types: UDP or TCP tunnel, fixed tunnel address, KNXnet/IP routing, KNX IP Secure, and a Home Assistant mode that reads the KNX integration's telegrams without a tunnel of its own.
- KNX Data Secure: import the keyring from ETS; secured telegrams are decrypted live and in the recording.
- Alarm notifications now come from the add-on itself, plus long-term statistics with an activity heatmap.

## 1.2.0 – 17 Oct 2026

- New: the "Health" tool. It reads known status addresses, reports addresses that went silent, watches cycles and checks plausibility, the datapoint type per sender and bus quality.
- New: commissioning checklist with notes and a PDF report.
- The communication map starts with an overview of all addresses and devices.
- Senders and receivers from the ETS project based on the flags; tunnel addresses shown separately in the topology.
- The add-on comes as a prebuilt image for amd64 and aarch64.

## 1.1.0 – 15 Oct 2026

- Alarm notifications through Home Assistant, a bus monitor with every frame including acknowledgements, and a topology with lines and couplers.

## 1.0.0 – 14 Oct 2026

Day one: within a single day an idea became the first version of the app, and by the evening it was already running as an add-on in Home Assistant's sidebar.

- KNXnet/IP tunnel connection, live group monitor, writing values.
- Group addresses from ETS as CSV or straight from the project file (.knxproj), PDF export of selected telegrams.
- Overview by rooms and objects, history charts, recordings with playback and a trigger recording with pre- and post-roll.
- Diagnostics: read status, find programming mode, check addresses, device info, line scan, communication map, statistics and project check.
- German and English, iPhone, iPad, Mac and the Home Assistant add-on.
