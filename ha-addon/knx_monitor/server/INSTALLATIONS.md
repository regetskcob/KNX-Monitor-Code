# Installationen im Server (Add-on und Busclear Box)

Eine Installation ist eine Anlage (Kunde, Baustelle, Zuhause) mit eigener
Busverbindung, ETS-Katalog, Keyring und Langzeitverlauf. Die Box wandert von
Kunde zu Kunde; gewechselt wird zur Laufzeit, der Verlauf der anderen bleibt
lesbar.

Code: `lib/src/installations.dart` (`Installations`, `InstallationService`,
`serveInstallations`), Tests: `test/installations_test.dart`.

## Datenordner

```
DATA_DIR/
  access.json            Box-Zugänge (global, privat)
  time-request.json      Zeitwunsch an den Host (global, privat)
  installations.json     {version: 1, active: "<id>", list: [{id, name, created}]}
  installations/<id>/
    server.json          Busverbindung (privat, nur über /api/bus)
    catalog.json, dpt_overrides.json, name_overrides.json, secure_keys.json, health.json, …
    history/             Tagesverlauf (JJJJ-MM-TT.ndjson[.gz], unsynced-*.ndjson)
    status/              Verfügbarkeit (availability-JJJJ-MM.ndjson)
```

`created` ist Epoch-Millisekunden (wie in der App).

**Migration** beim Start, wenn `installations.json` fehlt: `server.json`,
`catalog.json`, `dpt_overrides.json`, `secure_keys.json`, `health.json`,
`commissioning.json`, `diagnostics.json`, `availability.json`, `history/`,
`status/`, `recordings/`, `charts/` und `unsynced-*.ndjson` aus dem Root
wandern nach `installations/default/`. Name = `project` aus `catalog.json`,
sonst „Installation“. Bei leerem Datenordner entsteht eine leere `default`.
Wiederholbar (Index wird zuletzt geschrieben). Das Home-Assistant-Add-on läuft
danach unverändert mit genau dieser einen Installation.

Ids: `^[A-Za-z0-9_-]{1,64}$` (12 Hex-Zeichen der App, UUIDs passen).

## Endpunkte

Verwalten nur als Admin (Box-Passwort, mit dem Passwort gekoppeltes Gerät,
im Add-on jeder Ingress-Zugriff). Gerätezugänge ohne Admin-Recht lesen nur die
aktive Installation: `GET /api/installations` liefert ihnen nur sie, andere Ids
(auch `?installation=<id>` bei Verlauf, Statistik, Verfügbarkeit und ETS-Export)
antworten 403.
Fehler kommen als Text mit Status 400 (Name/Id ungültig), 403 (kein Admin),
404 (Installation unbekannt), 405, 409 (Id gibt es schon / aktive löschen).

| Methode | Pfad | Body | Antwort |
|---|---|---|---|
| GET | `/api/installations` | – | `{active: "<id>", list: [{id, name, created, active: bool}]}` |
| POST | `/api/installations` | `{id?, name}` | 201 `{id, name, created, active: false}` |
| POST | `/api/installations/active` | `{id}` | 200, wie GET (nach dem Wechsel) |
| PATCH | `/api/installations/<id>` | `{name}` | 200 `{id, name, created, active}` |
| DELETE | `/api/installations/<id>` | – | 204; aktive → 409; löscht den Ordner samt Verlauf |
| GET | `/api/installations/<id>/files/<rel>` | – | Datei bzw. mit `/` am Ende die Liste – wie `/api/files/`, nur lesen (sonst 405) |

`name` wird getrimmt, höchstens 80 Zeichen. Schickt die App ihre eigene `id`
mit, benutzen Box und App dieselbe; ohne `id` erzeugt der Server 12 Hex-Zeichen.
Anlegen wechselt nicht.

**Wechsel** (`POST /api/installations/active`): Verlauf schreiben, Tunnel
abmelden, alle offenen `/ws/bus` mit Code 1001 („Installation gewechselt“)
schließen, neue Busverbindung aus `installations/<id>/server.json` starten.
Alarm- und Katalogzustand beginnen neu. Die App verbindet den WebSocket neu und
liest danach `/api/bus` bzw. den ersten Status. Zeilen ohne gesicherte Zeit
(Box ohne Uhr) bleiben in der alten Installation und werden dort umgerechnet,
sobald die Uhr gestellt ist.

## Geänderte Endpunkte

- `/api/files/<rel>`: zeigt in die **aktive** Installation. Gesperrt (403):
  `access.json`, `server.json`, `box-password.txt`, `time-request.json`,
  `installations.json` und alles unter `installations/` – also auch
  `installations/*/server.json`. Den Ordner selbst listet die Ablage nicht.
- `GET /api/bus` und der Status über `/ws/bus` (Typ `0x02`) enthalten
  `installation: {id, name}`.
- `GET /api/box` enthält `installation: {id, name}`.
- `GET /api/bus/stats?days=7&installation=<id>` und
  `GET /api/bus/availability?from=…&to=…&installation=<id>`: ohne
  `installation` die aktive; unbekannte Id → 404.

## Für die App

- Im Browser (Add-on) bleibt die App im Root von `/api/files/`; der Server
  führt die eine Installation `default`.
- Nativ mit Box: Liste über `GET /api/installations`, Verlauf alter
  Installationen über `/api/installations/<id>/files/history/` und
  `/api/bus/stats?installation=<id>`.
- Box an neuen Kunden: `POST /api/installations {id: <App-Id>, name}`, dann
  `POST /api/installations/active {id}`, danach Busverbindung per `PUT /api/bus`
  und Katalog/Keyring per `/api/files/…` wie bisher.
