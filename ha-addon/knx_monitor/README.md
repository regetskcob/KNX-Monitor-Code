# Home Assistant Add-on: KNX Monitor

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

See what is happening on your KNX bus – right in the Home Assistant sidebar,
on any device, also on the go via the Home Assistant app.

KNX Monitor connects directly to your KNX IP interface or router and shows
every group telegram with the names, datapoint types and devices from your
ETS project. It is built for installers commissioning a building as well as
for owners who want to understand what their installation is doing.

## Features

- **Group monitor** – overview cards per function (lighting, heating,
  energy …), object list with last values and a live telegram stream with
  filters and history charts
- **ETS project import** – `.knxproj` (also password-protected) or a group
  address CSV; KNX Data Secure keyrings are supported
- **Diagnostics** – health check, commissioning checklist, project
  comparison, topology and communication map, bus monitor
- **Continuous recording** – the add-on stays connected without an open
  browser, keeps a daily history and explains gaps
- **Recordings** – trigger recordings, real-time replay and PDF export
- **Watchers and alarms** – Home Assistant notifications or push when a
  group address reports a fault
- **Connection types** – UDP/TCP tunneling, routing, KNX IP Secure, or the
  existing Home Assistant KNX integration

## Getting started

1. Install and start the add-on, then open **KNX Monitor** in the sidebar.
2. Pick your gateway (discovered automatically) or enter its IP address.
3. Import your ETS project to get names, datapoint types and devices.

Details on connection types, continuous recording, KNX Data Secure and the
configuration options are in the **Documentation** tab of this add-on.

## Support

Bugs and feature requests: <https://github.com/regetskcob/KNX-Monitor/issues>

**Vote on what comes next:** planned features are open issues on GitHub –
for example DALI lighting diagnostics, a native Home Assistant integration or
listening on the TP line directly. Give the ones you would use a 👍 and add a
comment with your setup; the votes decide what gets built first:
<https://github.com/regetskcob/KNX-Monitor/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement+sort%3Areactions-%2B1-desc>

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
