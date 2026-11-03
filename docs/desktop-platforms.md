# Desktop platforms: macOS, Linux and Windows

Goal: the app offers the same on all three desktop platforms, with the scope
of the iPad and iPhone app wherever that makes sense on a desktop.

## Current state

The core is plain Dart and behaves the same everywhere: tunnelling over UDP or
TCP, routing (multicast), IP Secure and Data Secure, gateway discovery,
catalog, history, recordings, charts, diagnostics and sending. Only the code
in `lib/platform/` and the plugins depend on the platform.

| Feature | macOS | Linux | Windows | Notes |
| --- | --- | --- | --- | --- |
| Tunnelling, routing, Secure | ✓ | ✓ | ✓ | `dart:io`; multicast on Windows without `reusePort` (fallback in `lib/platform/udp_io.dart`) |
| Gateway discovery | ✓ | ✓ | ✓ | see [Windows firewall](#2-windows-firewall) |
| Open files (ETS, CSV, recording, keyring) | ✓ | ✓ | ✓ | Linux via `xdg-desktop-portal` |
| Save CSV, PNG, text | ✓ | ✓ | ✓ | save dialog (`saveBytes`) |
| PDF export | share menu | save dialog | save dialog | `sharePdf` in `lib/ui/common.dart` |
| Printing | ✓ | ✓ | ✓ | `printing`; Linux needs CUPS |
| Data (settings, history) | ✓ | ✓ | ✓ | `getApplicationSupportDirectory` |
| Secure keys | ✓ | ✓ | ✓ | `flutter_secure_storage`; Linux via libsecret |
| Keep recording while minimized | ✓ | ✓ | ✓ | see below |
| Alarm and watcher notifications | – | – | – | **gap**, see below |
| Window 1100×760, title, icon | ✓ | ✓ | ✓ | |
| Distribution | signed through Apple | GitHub release (`.tar.gz` with `install.sh`) | not published yet | see below |

Verified: macOS release build; Linux release build (arm64, Ubuntu 24.04)
started under Xvfb (title, app ID, size, icon); analysis and tests. Windows is
only built in CI; a run on a real Windows machine is still missing.

## Platform details

- **Background:** `BackgroundController.onBackground`
  (`lib/platform/native_bridge.dart`) disconnects the tunnel 25 s after the
  app is paused. This is meant for iOS and Android, to free the tunnel slot on
  the gateway. On the desktop and in the browser it does not apply: a
  minimized window keeps recording.
- **PDF on Linux and Windows:** `Printing.sharePdf` only writes to the temp
  folder there and opens the file in the default program. `sharePdf` therefore
  shows the save dialog on these platforms, as for CSV and PNG.
- **App IDs:** Linux `de.regetskcob.knxmonitor` (`linux/CMakeLists.txt`);
  iOS and macOS `de.regetskcob.knx-monitor`; Android
  `de.kalkar_it.knxmonitor` (Kotlin namespace `de.regetskcob.knxmonitor`).
- **Linux:** window 1100×760 like macOS, window icon from
  `data/app_icon.png` in the bundle. `linux/packaging/install.sh` installs to
  `~/.local/opt/knx-monitor` and adds a desktop entry whose name matches the
  app ID; without it, GNOME and KDE Plasma on Wayland show a placeholder icon.
- **Windows:** window title "KNX Monitor", 1100×760, version info
  (`Runner.rc`) and app icon (`windows/runner/resources/app_icon.ico`).
- **CI** (`.github/workflows/ci.yml`): jobs `linux` and `windows` build on
  `app-v*` tags or by hand and upload `knx-monitor-linux` and
  `knx-monitor-windows` as artifacts. macOS is not built in CI; it is built and
  signed in Xcode. `tool/release.sh desktop` publishes the Linux build of a tag
  run as a public GitHub release.

## Open points

### 1. Notifications on the desktop (largest gap)

Today notifications are native on iOS and Android (`NativeBridge` →
`KnxNative.swift`, `MainActivity.kt`) and go through Home Assistant in the
add-on. On macOS, Linux and Windows `sendNotification`
(`lib/platform/notify_io.dart`) does nothing.

Proposal: `flutter_local_notifications` for macOS, Linux and Windows.

- `notify_io.dart`: iOS and Android stay on `NativeBridge`, the desktop uses
  the plugin. The interface (`sendNotification`,
  `requestNotificationPermission`) stays.
- Windows: the plugin needs an app name, AppUserModelID and GUID. Without an
  MSIX installer, notifications work only after registration on first start;
  the plugin does that itself.
- Linux: `org.freedesktop.Notifications` (D-Bus), icon from the bundle.
- macOS: ask for permission when notifications are turned on, as on iOS.
- New dependency with sub-packages (`timezone`, `clock`, D-Bus, C++/WinRT).

Alternative: native code per platform (Swift for macOS as on iOS, D-Bus
directly on Linux, WinRT on Windows). That would be three separate
implementations without tests, so the plugin is the preferred option.

### 2. Windows firewall

On the first UDP reception Windows asks whether the app may accept incoming
connections. Whoever clicks "Cancel" gets no answers from the gateway, and the
app only reports a timeout.

- Extend the timeout message on Windows with a hint about the firewall (not
  implemented yet).
- An installer (see 3) can create the rule.
- A TCP tunnel (KNXnet/IP 2.0) is not affected because the connection is
  outgoing. Gateway discovery and routing are.

### 3. Distribution

| Platform | Today | Options |
| --- | --- | --- |
| macOS | archive from Xcode, signed and distributed through Apple; no download in the GitHub release | – |
| Linux | `.tar.gz` with `install.sh` and `README.txt` | AppImage or Flatpak (Flathub); Flatpak brings the portal and a sandbox |
| Windows | folder with `.exe` (CI artifact only) | MSIX or a classic installer (e.g. Inno Setup), with code signing – otherwise SmartScreen warns |

For testers the CI artifacts are enough. The Windows format is not decided.

### 4. Tests on real machines

CI only builds. Once per platform, by hand:

- gateway discovery, connecting via UDP and TCP, routing
- import an ETS project, export a PDF, print
- minimize, wait 5 minutes, the history has no gap
- restart: settings and history are still there
- Windows: decline the firewall dialog – is the error message understandable?
- Linux: GNOME (Wayland) and KDE, once each
