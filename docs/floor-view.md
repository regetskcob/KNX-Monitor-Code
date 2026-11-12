# Bus on the floor plan

"Bus auf dem Grundriss" shows the installation on a floor plan: every point
stands for a device and carries one or more group addresses. A telegram to
one of them makes the point light up; points that have addresses but were
never heard stand out as silent. It is a technical view of the bus, not a
control panel: nothing in it sends.

Where it is:

- **App** (iOS, iPadOS, macOS, Android, Windows, Linux, browser): Menu ›
  Bus on the floor plan. Add a level, pick an image of the floor plan, tap
  to place points and choose their group addresses from the ETS project or
  the taught-in names. The first level is free, further levels belong to
  Plus.
- **Add-on and box**: the same screen in the browser. The server adds when
  each address was last in the recorded history, so silence shows over days
  and not only since the page was opened.
- **Home Assistant dashboard**: the card `custom:knx-monitor-floor-card`
  ("Busclear Grundriss" / "Busclear floor plan"), installed by the add-on
  next to the chart card.

In the demo house a sample level is drawn from the demo project, nothing is
saved there.

## States

| State | Meaning | Shape |
| --- | --- | --- |
| active | a telegram within the last seconds | halo around a filled disc |
| heard | a telegram earlier in the watched time | filled disc |
| not heard yet | has addresses, nothing heard so far | hollow ring |
| silent for long | nothing heard although the bus has been watched for twelve hours or more | ring with a warning sign |
| no address | not linked yet | small square |

The shapes differ, so the states do not depend on colour; in the app every
point carries the symbol of its kind and a spoken label with name, room and
state, and tapping it shows name, state and time under the plan. Reads do not
count as a sign of life: a read request is a question, not the device talking.

"Not heard yet" is neutral on purpose: many devices only send when they are
operated, so minutes after opening the view most of a house has said nothing.
The warning sign appears only after twelve hours of watched time, the same
patience the watcher "stopped sending" has. The monitor alone rarely watches
that long; with the add-on or box the recorded history (up to seven days)
carries the statement. Even then it is a hint to look, not a fault.

## File format

The view is the file `floor_view.json` in the installation's folder, images
next to it as base64 JPEG in `floor_view_images/`. Model and reader:
`lib/model/floor_view.dart`; the server reads the same file in
`ha-addon/knx_monitor/server/lib/src/floor_view.dart`.

```json
{
  "format": "busclear-floor-view",
  "version": 1,
  "source": "own",
  "floors": [
    {
      "id": "f1",
      "name": "Ground floor",
      "aspect": 1.4,
      "image": "floor_view_images/f1.jpg.b64",
      "rooms": [{ "name": "Living", "x": 0, "y": 0, "w": 0.55, "h": 0.6 }],
      "points": [
        { "id": "p1", "name": "Living light", "kind": "light", "room": "Living",
          "x": 0.27, "y": 0.27, "addresses": [2048, 2304] }
      ]
    }
  ],
  "nextId": 2
}
```

- Positions and sizes are shares of the plan (0 to 1), `aspect` is width
  divided by height, group addresses are numbers (`main << 11 | middle << 8 |
  sub`).
- `kind`: `light`, `button`, `blind`, `socket`, `heating`, `sensor`,
  `contact`, `other`.
- `source`: `own` for a view drawn in the app. Another tool that writes the
  file can name itself; the app then shows the view and leaves editing to
  that tool.
- A newer `version` is never opened and never overwritten.

Readers treat the file as foreign input: wrong types become defaults, lists
and texts are cut at fixed limits, and an image is only read from the image
folders under a generated name (`[0-9a-z]{1,32}.jpg.b64`), whatever the file
says. Names are shown as plain text everywhere, also on the dashboard card.

## Server and card

`GET /api/floor-view` returns the sanitized view, `last` (group address →
time of the last telegram in milliseconds), `since` and `now`;
`GET /api/floor-view/image?floor=<id>` returns the JPEG of a level. Both sit
behind the same access check as the chart endpoints (Ingress in Home
Assistant, the box's sign-in or a paired device on the box) and are read-only;
other methods answer 405.

The server keeps what it knows per installation: after a switch nothing of the
previous one is shown. The history is read once per address, in slices and
never by two scans at a time; until it is done the answer carries
`loading: true`. Measured with seven days of 100,000 telegrams each: about
0.5 s on a Mac, an estimated 5 s on a Raspberry Pi 4, without holding up the
bus ([performance.md](performance.md#history-scan-of-the-bus-view)).
Images are decoded one at a time, kept while the file is
unchanged and answered with an `ETag` (304 when the browser already has it).

```yaml
type: custom:knx-monitor-floor-card
floor: f1 # optional, the first level otherwise
title: Ground floor # optional
```

The card polls every five seconds while the page is visible. It builds its
elements with `createElement` and `textContent` only.
