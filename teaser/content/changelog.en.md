---
title: "Changelog"
description: "What the latest versions of KNX Monitor brought to the app, the Home Assistant add-on and the KNX box, newest first."
layout: "page"
slug: "changelog"
---
What the latest versions of KNX Monitor brought, newest first. App, Home Assistant add-on and KNX box share one version number. Every version is on [GitHub](https://github.com/regetskcob/KNX-Monitor/releases); in Home Assistant the add-on shows the same notes before an update.

## 1.9.3 – in preparation

- Accounts are gone for now: the app no longer signs in and talks to no account service. Your data on the device stays as it is.

## 1.9.2 – 1 Nov 2026

- New for anyone planning or building: the home plan, no gateway needed. You go through your everyday life, and that becomes a room book and floor plan for talking to your contractor. You set lights and sockets as switchable, dimmable or permanently powered; the app works out the channel demand and exports the device list as CSV and PDF.
- With Plus: all levels including the outdoor area, checks such as a button inside a door swing, deadlines per construction type, offer check, PDF with dimensions and DXF. The catalog is compiled to the best of our knowledge and does not replace electrical planning.
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
