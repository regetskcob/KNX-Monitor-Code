# Diagnostics package

A support feature: a user sends a problem together with a bus recording and
the project; the recipient opens the package in the app and replays it.

Code: `lib/export/diagnostics_bundle.dart` (package, `Scrubber`),
`lib/model/annotation.dart` (comments and screenshots),
`lib/model/findings.dart` (findings), `lib/ui/recording_timeline.dart`
(timeline).

## Where to create it

- Menu › Tools › Check › "Diagnostics package" (with a running session)
- Error banner after a connection loss in the monitor (icon next to
  "Reconnect")
- Error message on the connect screen (icon next to the message)
- Notice after an unexpected end of the app (`lib/model/crash_guard.dart`,
  native apps in the foreground only); the lines of the previous run are in
  the log

The package is then shared via the share sheet on iOS, iPadOS and Android,
saved via the save dialog on macOS, Windows and Linux, and downloaded in the
Home Assistant add-on.

## Contents (ZIP)

| File | Content |
| --- | --- |
| `diagnostics.json` | format version, problem description (what happened, what was expected), time, period, counters, technical details (in the add-on and on the box also unexpected server restarts) |
| `recording.json` | telegrams in recording format (`Recording.toJson`), without raw cEMI data |
| `project.json` | catalog (`GroupCatalog.toJson`) and custom datapoint types |
| `secure.json` | Data Secure telegrams with time, source and destination only (as seen on the bus without a keyring) |
| `log.txt` | recent app messages and errors (`AppLog`), scrubbed |
| `shots/<id>.jpg` | screenshots for the problem description and for comments (at most 15, longest edge 1920 px, JPEG) |

Never included: IP addresses, host names, URLs, MAC and serial numbers,
passwords, keyring and keys, user names, e-mail addresses. The project name
becomes `Project`, installation names are left out. Names of group addresses
and devices are included, but can be switched off before export (addresses
and product names remain).

Scrubbing: `Scrubber` in `lib/export/diagnostics_bundle.dart` replaces
patterns and known private names (installations, gateway host, serial number
and MAC, project and file name, keyring project) in free text
(`knownPrivateNames`).

## Opening a package

Recordings › Import › choose the ZIP. In the native apps this creates a new
installation "Diagnostics <date>" with the project; the recording belongs to
it and opens in the player, and the problem description is in its note.
Disconnect first. In the add-on (one installation) only the recording is
imported.

The app refuses packages with a newer format (`diagnosticsFormatVersion`,
currently 2). Version 2 adds comments (`annotations` in `recording.json`) and
screenshots (`shots/`; those for the problem description are listed under
`shots` in `diagnostics.json`). Version 1 can still be opened.

After opening, the app shows the **findings**: problem description with
screenshots, automatic hints from technical details, traffic and log
(`lib/model/findings.dart`), the comments (tapping one opens the timeline at
that point), the busiest addresses, the technical details and the log with
errors highlighted.

## Comments and timeline

- Comments on the user's own installation are stored per installation in
  `annotations.json` (`AnnotationStore`), independently of recordings. They
  are added from the telegram details ("Comment"), a chart (at the
  crosshair), the timeline of a recording and "Report a problem". Commented
  telegrams carry a flag in lists; all comments are listed under Tools ›
  Comments.
- A comment holds a time, text, up to 3 screenshots and optionally a
  reference: a telegram (with its raw value, so it stays understandable
  without a recording) or a chart (addresses and time range).
- The package includes the comments in its period and, optionally (on by
  default), older ones from the last 30 days. Without names, room and device names are replaced in
  the comment text too.
- Recordings from other people's packages keep their comments inside the
  recording (`AnnotationScope`), so they do not mix with those of the own
  installation.
- Screenshots (`shots/` in storage): scaled down to 1920 px, JPEG quality 85,
  without EXIF. A quota of 100 MB for all of them; they are deleted together
  with their comment or recording, discarded ones immediately.
- Timeline (`lib/ui/recording_timeline.dart`): one row per group address,
  ticks by telegram type, drag and zoom; the pointer shows the telegram,
  tapping adds a comment, the time axis controls the player.

## Report a problem

Tools › Check › "Report a problem": start a recording, reproduce the problem,
tap "It happened now" each time it occurs (a comment at that moment), then
create the diagnostics package of the session from its start and share it.
