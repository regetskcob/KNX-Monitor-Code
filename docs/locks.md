# Locks: who locked what when

A locked channel takes commands and does nothing. "Locks"
(`lib/ui/locks_screen.dart`, `lib/model/locks.dart`) makes that visible from
the recording: what is locked now, who locked it and since when, and for every
past lock its start, end, duration and who released it. Nothing is sent.

## Which addresses are locks

| Recognised by | Reading |
| --- | --- |
| Name contains Sperr…, lock, disable, inhibit, Zwangsführung, forced | 1 locks |
| Name contains Freigabe, enable, or the type is 1.003 | 0 locks |

Only 1-bit addresses count; the name decides before the type. Whether 1 or 0
locks differs between manufacturers and is not in the telegram, so every
address can be turned around by hand. The choice is stored per installation in
`lock_polarity.json`.

## Lock periods

`lockTracks` walks the recording in order. The first "locked" telegram opens a
period and names who locked; further "locked" telegrams (cyclic sending) only
count as repeats; the first "free" telegram closes it and names who released
it. Read requests say nothing. A period that starts with a response to a read
request is shown as "since at least": the lock may be older than the
recording.

The lock acts on the devices that receive the address according to the
project's associations; the sender is the device that sent the telegram.

## Where else it shows

When operating a channel from its drawing or in the channel check
(`docs/device-operation.md`) the status feedback stays away, and a lock object
of that channel is set, the message says since when and by whom it is locked
instead of only "no feedback".

## Limits

Locks set before connecting are unknown until the address sends again or is
read. Locks inside a device (parameters, manual operation, a lock without a
group address) are not on the bus.
