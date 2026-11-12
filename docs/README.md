# Documentation

Technical documentation of Busclear. Users of the Home Assistant add-on find
their guide in [ha-addon/knx_monitor/DOCS.md](../ha-addon/knx_monitor/DOCS.md).
The same documents are published as the
[wiki](https://github.com/regetskcob/KNX-Monitor-Code/wiki), generated from
this folder on every release; changes go here.

## Overview

- [architecture.md](architecture.md): the app, the server, how they reach the
  bus and where each part lives in the code.

## Runtime

- [addon-recording.md](addon-recording.md): the add-on server, its permanent
  bus connection, recording and the WebSocket protocol to the views.
- [event-channel.md](event-channel.md): the event channel `/ws/events` for
  automations without Supervisor (Home Assistant Container, ioBroker): format,
  access, sequence numbers, slow clients.
- [health-check.md](health-check.md): the health check the server runs for
  Home Assistant without the app: switching it on, the rules, the routes below
  `/api/ha/health`, the result format.
- [knx-box.md](knx-box.md): the Raspberry Pi image: first boot, storage and
  compression, time without RTC, networking, services.
- [kberry.md](kberry.md): KNX TP through the Weinzierl kBerry: Pi setup,
  FT1.2, cEMI, sending and receiving. Written to be reused in other projects.
- [desktop-platforms.md](desktop-platforms.md): what differs on macOS, Linux
  and Windows.
- [tap-points.md](tap-points.md): several connections to one installation:
  merging, the self-measuring window, gaps, Data Secure, sending, limits.
- [performance.md](performance.md): behaviour under bus load.
- [resilience-tests.md](resilience-tests.md): tests on real hardware
  (add-on watchdog, rollback of the box setup, add-on upgrade).

## Data and security

- [security.md](security.md): encryption at rest, backups, app lock, KNX IP
  Secure and Data Secure, access to add-on and box, read-only mode, outbound
  connections, reporting vulnerabilities.
- [keys.md](keys.md): the keys that tell installations, boxes and app
  instances apart, who creates them and where they travel.
- [backup-format.md](backup-format.md): the `.knxbackup` file format, with a
  decryption example, and the box backup (whole box or container, restore,
  encrypted KNX Secure keys).
- [diagnostics-package.md](diagnostics-package.md): what the diagnostics
  package contains and how it is anonymised.
- [handover-format.md](handover-format.md): the file formats `.knxhandover`
  (handover package), `.knxreport` (fault report) and `.knxcustomers`
  (customer files for a second own device), with a decryption example,
  limits and compatibility rules.
- [floor-view.md](floor-view.md): the bus on a floor plan: states, the open
  file format `floor_view.json`, the server endpoints and the dashboard card.

## KNX and ETS

- [group-addresses.md](group-addresses.md): naming schemes the app recognises.
- [dali.md](dali.md): DALI lighting behind a KNX-DALI gateway: decoded datapoint
  types, the model in `dali.json`, alarms, the emergency lighting log, gateway
  profiles.
- [mcp-server.md](mcp-server.md): the MCP server for AI tools: read-only
  access to history, findings and the project check.
- [xknx-editor.md](xknx-editor.md): working with the XKNX Editor: importing
  `.xknx` projects and handing findings over.
- [ets-round-trip.md](ets-round-trip.md): taking changes from Busclear
  back into the ETS project.

## Project

- [releasing.md](releasing.md): how add-on, box and app releases are built and
  published.
- [release-security.md](release-security.md): supply chain, signed images and
  how to verify them.
- [third-party-notices.md](third-party-notices.md): code and data from other
  projects.
- Contributing: [../CONTRIBUTING.md](../CONTRIBUTING.md). Licence:
  [../LICENSE](../LICENSE), trademarks: [../TRADEMARKS.md](../TRADEMARKS.md).
