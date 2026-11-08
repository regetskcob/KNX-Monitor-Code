# Busclear

Bus monitor and diagnostic tool for KNX. Available today as a Home Assistant
add-on and for Linux; the apps for iPhone, iPad, Android, Mac and Windows
follow in the coming weeks. The Busclear Box, a Raspberry Pi that records on site,
is a preview, set up with the app, on an IP gateway or directly on the bus with the kBerry module; its image is listed under Downloads.

**Website:** <https://busclear.de>

This repository hosts the Home Assistant add-on repository, the Linux and
Busclear Box downloads, and the issue tracker. The Busclear integration for Home
Assistant (HACS) lives in
[regetskcob/KNX-Monitor-HA](https://github.com/regetskcob/KNX-Monitor-HA). The source code is open under GPLv3
in [regetskcob/KNX-Monitor-Code](https://github.com/regetskcob/KNX-Monitor-Code),
the technical documentation in its
[wiki](https://github.com/regetskcob/KNX-Monitor-Code/wiki). Questions about
the code also go to the issues here.

[![Add repository to my Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor)

## Your data stays yours

Busclear works on your network and stores on your devices. You need no
account, and it contains no analytics or advertising libraries.
Project, telegrams, recordings and keys stay on your device, your Busclear Box or
your Home Assistant, and only leave when you share them.

From version 1.9.1 the apps encrypt their files with AES-256-GCM (key in the
system keychain; unencrypted on Linux without libsecret, and for settings such
as the gateway), offer an optional app lock, and back up everything to a file
with its own password in an [open format](BACKUP-FORMAT.md). The add-on and the
Box do not encrypt their files themselves; they rely on your backups and on
physical access to the host. Details and limits:
[privacy policy](https://busclear.de/en/privacy/).

## Downloads

- **Linux:** [latest release](https://github.com/regetskcob/KNX-Monitor/releases/latest)
- **iPhone, iPad, Mac:** App Store, coming in the next weeks
- **Android:** Google Play, coming in the next weeks
- **Windows:** coming in the next weeks
- **Busclear Box (Raspberry Pi image, preview):** releases tagged `box-v…`
- **Docker (ioBroker, NAS, Proxmox):** `ghcr.io/regetskcob/knx-monitor`, see [docker/README.md](docker/README.md)

## Home Assistant add-on

1. Click the button above, or go to **Settings → Add-ons → Add-on Store → ⋮ →
   Repositories** and add `https://github.com/regetskcob/KNX-Monitor`.
2. Install **Busclear**, start it and enable **Show in sidebar**.

Configuration: [DOCS.md](ha-addon/knx_monitor/DOCS.md).

## Support

Bugs, questions and requests: [issues](https://github.com/regetskcob/KNX-Monitor/issues).

Please do not upload your ETS project (`.knxproj`) or recordings publicly, they
can contain addresses, room names and passwords.

Planned features are open issues too. [Vote with 👍](https://github.com/regetskcob/KNX-Monitor/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement+sort%3Areactions-%2B1-desc) on the ones you
would use and tell us about your setup in a comment – the votes decide what
comes first.

Security issues: see [SECURITY.md](SECURITY.md).

## License

Busclear is free software under the GNU General Public License v3.0, see
[LICENSE](LICENSE) and the source in
[regetskcob/KNX-Monitor-Code](https://github.com/regetskcob/KNX-Monitor-Code).
The names Busclear and Busclear Box, the logo and the app icons are not covered
by the licence, see its
[TRADEMARKS.md](https://github.com/regetskcob/KNX-Monitor-Code/blob/main/TRADEMARKS.md).
Builds from the App Store and Google Play are also subject to the terms of the
store. Versions released before 20 October 2026 were published under the MIT
License and remain available under it.

## Trademark

KNX is a trademark of the KNX Association. This project is not affiliated with
or endorsed by the KNX Association.
