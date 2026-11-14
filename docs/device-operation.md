# Operating devices from their drawing, channel check

The device sheet draws an actuator or push button with live values
(`lib/ui/actuator_view.dart`, `lib/ui/push_button_view.dart`). Two tools build on
those drawings. Both send group telegrams like a push button would; the manual
keys on a DIN-rail device act locally and are not on the bus.

## Operate

The chip "Operate" above the drawing (`lib/ui/operate_mode.dart`) arms sending.
It is off at every start. While it is on, a tap on a channel or key sends
instead of selecting it.

What a tap sends is decided in `lib/model/channel_control.dart` (`controlOf`):

| Channel | Sent | Confirmed by |
| --- | --- | --- |
| Switching, dimming (switch object) | the opposite of the current state; a key pair sends on and off | the status feedback (DPT 1) within 2 s |
| Blind, shutter | up, down or stop from a sheet; a key pair sends up and down | nothing (a blind reports a position) |
| Heating valve | nothing: valves belong to the controller | – |

Only switching addresses (DPT 1) that are not named as a status feedback are
sent to. Success is what the actuator reports back, not what was sent: a
locked channel takes the telegram and stays as it is, and the message then
says "no feedback".

Channels whose name sounds like a gate, door, lock, alarm or central function
ask for confirmation every time. The notice before the first write
(`lib/ui/write_confirm.dart`) applies as everywhere else.

Limits: the channel-to-address links come from the ETS project. Without a
project, or for a device without associations, there is nothing to operate.

## Channel check (Pro)

"Check channels" on an actuator's device sheet
(`lib/ui/channel_test_screen.dart`, `lib/model/channel_test.dart`) answers "which
channel is which lamp":

1. The app switches one channel on and waits for its status feedback.
2. The installer says what reacted: the right load, a wrong one, or nothing,
   with an optional note.
3. The app switches the channel off again and goes on to the next.

Blinds, cautious channels and channels without a switching address are not
switched by the app; they are triggered by hand and only rated. Leaving the
screen switches a channel off that the check switched on.

Results are stored per installation in `channel_tests.json`, by device and
channel label, and can be shared as text. Where the channel's status address is
on the commissioning list, it is ticked off or marked as a problem there.

## Rooms

"Rooms" (`lib/ui/room_control_screen.dart`, `roomControls` in
`lib/model/channel_control.dart`) lists everything the project lets you switch,
by room, from the object index: a switch for switching objects, up/stop/down
for blinds. It uses the same rules as operating from a drawing. It is a test
page in the project's own names, not a visualization.

Below every switch it says why a display may show the wrong state
(`statusFinding`):

| Finding | Meaning |
| --- | --- |
| feedback matches | the status feedback has the value of the last command |
| no feedback in the project | the object has no status address; a display can only guess |
| feedback contradicts the command | the status came right after the command with another value, or never followed it: locked, or wrongly linked. A status that changed more than 5 s later is taken as the truth (switched from elsewhere). |
| feedback does not answer a read | "Read feedback" sent a read request and no value came within 2 s; displays that read at start stay empty |

"Read feedback" sends one read request per status address, one after another.

## Last telegram per object

The object list of a channel shows, below each object, when its value came,
from which device, and the value before (`ChannelObjects` in
`lib/ui/actuator_view.dart`). The previous value is looked for in the last
5000 telegrams of the recording.
