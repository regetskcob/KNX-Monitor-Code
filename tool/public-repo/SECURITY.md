# Security Policy

## Supported versions

Only the latest release of the app, of the Home Assistant add-on and of the KNX
Box receives security fixes. The operating system of a Box does not update
itself.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's
[private vulnerability reporting](https://github.com/regetskcob/KNX-Monitor/security/advisories/new)
instead. You will get a response as soon as possible; please allow reasonable
time for a fix before disclosing details.

## Scope

KNX Monitor talks to KNX IP gateways on the local network, runs as an add-on
inside Home Assistant behind Ingress, and as the KNX Box on a Raspberry Pi.
Relevant reports include, for example:

- ways to reach the add-on's WebSocket/HTTP server without Home Assistant
  authentication
- leaking ETS project data, passwords or recordings
- sending telegrams to the bus without user action
- reaching the KNX Box without its password, or changing it without user action
- reading the apps' encrypted files without the key from the system keychain, or
  a backup file without its password
- getting past the app lock on a device
- using the add-on's UDP relay to reach hosts outside the local network
  (it only forwards KNXnet/IP packets to private, VPN and multicast addresses)

Known limits, not vulnerabilities: the app lock and the file encryption do not
protect against malware under the same user account. Without a usable keychain
(Linux without libsecret) the app's files stay unencrypted, and settings such as
the gateway are not encrypted. Add-on and KNX Box store their data unencrypted.
A browser on the Box's Wi-Fi uses plain HTTP, so the Wi-Fi password is the
protection there; apps paired from version 1.9.2 use HTTPS with the Box's own
certificate. Whoever holds the Box's SD card can read everything on it.

Plain KNXnet/IP tunneling is unencrypted; use KNX IP Secure and Data Secure
where the installation supports them. Weaknesses of the KNX protocol itself are
out of scope.
