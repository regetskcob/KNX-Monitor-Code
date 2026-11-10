# Keys

Busclear runs in several places at once: the app on a phone and a laptop, a
box at a customer's, the add-on in Home Assistant, a handover package on its
way from the electrician to the home owner. This page says how each thing is
told apart across all of them, so that "the same installation" means the same
everywhere.

Three rules hold for every key on this page:

- **A key names something, it proves nothing.** Knowing the key of an
  installation or a box grants no access. Access stays with passwords, device
  tokens and the questions the app asks before it shares a project or a
  keyring.
- **A key is created once and never changed.** Whoever creates the thing
  creates its key; everyone else copies it.
- **Everything from outside is checked.** A key from a box, a package or a
  backup is only stored if it has the right form (`isKey` in
  `lib/model/keys.dart`).

A new kind of key is added here first, then in the code.
`test/keys_test.dart` fails when code generates identifiers in a file this
page does not list.

## What a key cannot do

The installation key travels: it is in every handover package and every fault
report, and those are files people pass around. So it is treated as public.
Nothing in app, server or account backend accepts a key in place of an id, a
password or a token:

- **Server (box, add-on).** No request is authorised by a key. Paths take the
  local id, never the key; `/api/installations/<key>/…` answers 404. Setting
  a key or creating an installation with one needs admin rights like any
  other change. A device access without admin rights sees the active
  installation only, and with it only that one's key.
- **App and box.** A box that names the key of an installation on this device
  is not connected with it by that. The app connects the two only if they
  share the id from before keys existed, if the app itself took the
  installation from that box or put it there, or after the user confirmed it
  (`InstallationStore.acceptBoxClaim`). Until then the app lists the claim
  (`boxClaims`) and exchanges nothing: no project, no keyring, no history. The
  questions before a project or a keyring goes to a box stay as they are.
- **Handover package and fault report.** A package only ever lands in an
  installation that came by handover itself, never in one the user created,
  and only when the user opens it. A fault report adds a report to the
  installation it names and reads nothing from it.
- **Account backend.** It never stores an installation key in the clear and
  has no query by it; whether two accounts know the same installation cannot
  be told there.

Two things follow from this and are intended:

- **The key of an older installation can be computed.** It is derived from
  the installation's id, and that id is in handover packages and fault reports
  too (`origin`). Whoever has such a file knows both. Nothing depends on the
  key being unknown.
- **Id and key together are what a box is matched by.** A box the user paired
  that names both the id and the key of an installation here counts as holding
  that installation, as it did by id alone before keys existed. Pairing is the
  trust decision; what then goes to the box is still asked per address and
  certificate. An id with another key, or a key under another id, is only a
  claim (`boxClaims`).

`ha-addon/knx_monitor/server/test/installations_test.dart` and
`test/keys_test.dart` hold these as tests.

## Overview

| Thing | Key | Form | Created by | Lives in |
|---|---|---|---|---|
| Installation | installation key | UUID | the app, or the server for installations it creates itself | `installations.json` (app and server) |
| Box or add-on | box key | UUID | the server on first start | `installations.json` on the server |
| App on a device | app instance key | 32 hex characters | the app on first use | settings of the device |
| Device access on a box | device id | 12 hex characters | the server when pairing | `access.json` on the box |

Besides these there are ids that only count in one place and never serve to
recognise something elsewhere: the folder name of an installation, the id of a
handover package, of a visit or of a note.

## Installation key

An installation is one physical KNX installation: one building, one bus. Its
key is a UUID that is the same wherever the installation is known.

**Key and id are two things.** The id of an installation is the name of its
folder (`installations/<id>/`) and part of its settings keys. It is local: the
same installation may have another id on another device. The key is what
identifies it.

Where the key comes from:

- **New installation in the app:** the id is 12 random hex characters, the key
  is derived from it (`derivedInstallationKey`, UUID version 5 style). Every
  device and every app version arrives at the same key for the same id, also
  for installations from before keys existed, and also after an older app
  version rewrote the index without the key.
- **Installation the server created** (the first one of every box and add-on
  has the id `default`): the server generates a random key. An id like
  `default` exists on every box, so nothing may be derived from it. Until the
  app has heard the key from the server, it holds a placeholder
  (`Installation.keyIsPlaceholder`) that never leaves the device.
- **Installation from a handover package:** it keeps the key from the package,
  whatever id it gets on the customer's device.

Where the key travels:

- **Box and add-on.** The app sends the key when it creates an installation on
  a box (`POST /api/installations` with `key`) and supplies it for
  installations an older app created (`PATCH /api/installations/<id>` with
  `key`, accepted once). The server lists it with every installation and in the
  bus status.
- **Matching app and box.** `InstallationStore.syncBox` decides by key which
  installation here is which one there, for installations the app connected
  with that box (see above; the key alone connects nothing). A second box whose installation is
  also called `default` gets its own installation in the app with a fresh
  local id; `boxIdOf` translates for the calls to the box. For a box that does
  not know keys yet the id decides, as before.
- **Handover package.** The key is part of the payload, encrypted together
  with it when the package has a password. A newer package for an installation
  that came by handover before updates that installation instead of creating a
  second one. Opening a package on the device it was made on creates a copy
  with a key of its own: two installations on one device never share a key.
- **Fault report.** It carries the key next to the id of the installation at
  the electrician's, so the report also finds its installation on a device
  where that one has another id.
- **Backup and sync between the user's devices.** The key is part of the
  installation's index entry and moves with it.

## Box key

Every box and every add-on has a UUID, generated on first start and stored in
`installations.json`. The server reports it as `box` in `/api/installations`
and, on a box, as `key` in `/api/box`.

It tells boxes apart after their address, name or certificate changed, and it
is the box's own claim. What may go to a box (project, keyring) is still
decided per address and certificate, never per key: a box that copies
another one's key gains nothing.

The key lives in the data folder. A restored data folder is the same box; a
data folder whose index was lost and rebuilt from the installation folders is
a new one.

## App instance key

The app on one device has one key (`AppInstance.id`), 32 random hex
characters in the device's settings. It never leaves through a backup: a
backup restored on another device is another app instance.

When the app pairs with a box, it sends this key along (`app` in
`POST /api/box/pair`). The box stores it with the device access and lists it
in `/api/box/devices`, so the owner of a box can tell whose access each entry
is, for example when an electrician's device gets access to a home owner's
box. The access itself is the token, not the key.

## Adding a key

1. Describe it here: what it stands for, who creates it, where it travels.
2. Generate it in one place and validate it wherever it comes from outside.
3. Add the file to the list in `test/keys_test.dart`.
