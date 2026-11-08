# Standard für App-Repos

Gilt für alle Flutter-App-Repos (KNX Monitor, Panzergefecht, Jagdaufseher, Kalkar
kompakt und alle neuen). Ziel: Jedes Projekt läuft gleich ab und legt gleich ab. Was ein
Projekt anders macht, steht in seiner `CLAUDE.md` und in `tool/werkbank.conf`.

## Ordnerstruktur

Jede Datei hat genau einen Ort. `werkbank layout` (Teil von `werkbank verify` und der CI)
lehnt unbekannte Einträge auf oberster Ebene und Medien außerhalb ihrer Ordner ab.

| Ordner | Inhalt |
|---|---|
| `lib/` | App-Quellcode |
| `test/` | Unit-, Widget- und Golden-Tests; Goldens in einem Unterordner `goldens/` |
| `integration_test/`, `test_driver/` | Tests auf Gerät oder Simulator, Store-Aufnahmen, Driver-Einstiege |
| `assets/` | Dateien, die in die App gebündelt werden – nur die |
| `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`, `tvos/`, `watchos/` | Plattformprojekte (Flutter-Standard, tvOS/watchOS über die Flutter-Forks) |
| `docs/` | Doku als Markdown; Bilder in `docs/images/<thema>/`, gedruckte Dokumente in `docs/pdf/` (Quellen und `build.sh` in `docs/pdf/<dokument>/`) |
| `tool/` | Skripte des Projekts; ein Werkzeug mit mehreren Dateien bekommt einen eigenen Ordner. `tool/werkbank/` ist die Kopie der werkbank, `tool/werkbank.conf` ihre Einstellung |
| `store/` | Alles für die Stores (Aufbau unten). Eingecheckt, außer das Projekt hält es privat – dann in `.gitignore`, und die `CLAUDE.md` sagt es |
| `site/` | Landingpage (Hugo); was sie ausliefert, liegt in `site/static/` oder `site/assets/` |
| `supabase/` | Backend (Migrationen, Funktionen, Vorlagen) |
| `build/` | Alles Erzeugte, ignoriert. `flutter clean` löscht es – was bleiben soll, gehört nicht hierhin |

Wurzeldateien: `README.md`, `CLAUDE.md`, `LICENSE`, bei offenen Projekten `CONTRIBUTING.md`,
`SECURITY.md` und `TRADEMARKS.md`, `CHANGELOG.md` (ggf. `CHANGELOG.de.md`),
`pubspec.*`, `analysis_options.yaml`, `l10n.yaml`, `dart_test.yaml`, `build.yaml`, `.mcp.json`,
`Gemfile*` (fastlane) und `package*.json` (Supabase-CLI und andere Node-Werkzeuge).
Weitere Wurzelordner nur für eigenständige Produkte neben der App (z. B. `ha-addon/`,
`box/` bei KNX Monitor), eingetragen in `WB_TOP_EXTRA`.

### `store/`

```
store/
  ios/metadata/                    der fastlane-deliver-Baum: <de-DE|en-US>/ mit den Texten,
                                   dazu review_information/, copyright.txt, Kategorien
  ios/screenshots/<de-DE|en-US>/   fertige Screenshots, Präfix nach Gerät: iphone69_01_<name>.png, ipad13_…
  ios/review/                      weitere Hinweise und Bilder für die App-Prüfung (was deliver
                                   nicht hochlädt)
  android/metadata/<de-DE|en-US>/  Texte und images/ im fastlane-supply-Format
                                   (images/phoneScreenshots/, sevenInchScreenshots/, tenInchScreenshots/,
                                   featureGraphic.png, icon.png)
  macos/screenshots/<de-DE|en-US>/
  raw/<gerät>/<de|en>/             Rohaufnahmen vor dem Rahmen (gerät: iphone, ipad, android-phone,
                                   android-tablet, mac, …); Querformat als <de|en>-land
  graphics/                        Banner, OG-Bilder und andere Store-Grafiken
  social/                          Beiträge für soziale Medien (optional)
  release/<version>/               Archiv hochgeladener Builds (immer ignoriert)
  archiv/                          alte Läufe, Sicherungen, Logs (immer ignoriert)
```

Sprachen: Store-Ordner heißen wie die Stores (`de-DE`, `en-US`), Rohaufnahmen wie die
App-Sprache (`de`, `en`).

## Ablauf

Jedes Projekt hat **einen** Einstieg `tool/release.sh <befehl>` (Vorlage:
`release.sh.example` im werkbank-Repo). Die gemeinsamen Schritte
ruft es über `tool/werkbank/bin/werkbank` auf; was nur das Projekt hat (Add-on, Box,
Watch-App, Seiten-Deploy), steht als eigener Befehl daneben.

| Befehl | Was | Quelle |
|---|---|---|
| `verify` | vor jedem Push: Layout, Übersetzungen, Format, Analyse, Tests, dann die Hooks `verify_quick_extra` und `verify_extra`; grün bei sauberem Arbeitsbaum merkt es sich den Commit (Stempel) | `werkbank verify` |
| `push [args]` | `git push`, danach – wenn `verify` genau diesen Commit geprüft hat – Status `werkbank/verify` auf GitHub, damit die PR-CI ihre Prüfungen überspringt | `werkbank push` |
| `android` | signiertes AAB (baut fastlane oder ein Projektskript, nimmt `werkbank collect aab <pfad> [variante]` es auf) nach `build/release/<app>-<version>.aab`, Prüfung gegen den Debug-Schlüssel, Symbole wegsichern | `werkbank android` |
| `ios` | IPA nach `build/release/<app>-<version>.ipa`, mit `--upload` zu App Store Connect | `werkbank ios` |
| `changelog [--draft]` | Changelog-Abschnitt der Version in allen Sprachen fertig? `--draft` macht aus „Unreleased“ die Version | `werkbank changelog` |
| `notes [--draft]` | Release-Texte des Builds vollständig? `--draft` legt Entwürfe aus den gemergten PRs an | `werkbank notes` |
| `upload-apple <xcarchive>` | Archiv (iOS, macOS) zu App Store Connect, mit dem in Xcode angemeldeten Konto | `werkbank upload-apple` |
| `resolved` | schlägt fehl, solange ein Store-Build `ios/**/Package.resolved` oder `macos/**/Package.resolved` geändert hat | `werkbank resolved` |
| `upload-play [aab] [track]` | AAB mit Versionshinweisen in eine Play-Spur (Dienstkonto) | `werkbank upload-play` |
| `devicetest` | Integrationstests nacheinander auf allen angeschlossenen Geräten, Bericht in `build/devicetest/` | `werkbank devicetest` |
| `shots` | Rohaufnahmen nach `store/raw/` | Projekt (Simulator über `werkbank sim`) |
| `graphics` | aus `store/raw/` die fertigen Bilder in `store/<plattform>/…` | Projekt |
| `site` | Landingpage bauen und ausliefern | `werkbank site` (Abschnitt Landingpages) |

- **Version** nur in `pubspec.yaml` (`x.y.z+build`); Skripte lesen sie mit `werkbank version`.
- **CI** läuft auf Pull Requests (Linux) mit denselben Schritten wie `verify --quick`; teure
  Builds (macOS, Windows) nur auf Tag oder von Hand. Release-Builds entstehen lokal.
- **Stempel statt doppelter Prüfung:** Actions-Minuten privater Repos sind knapp (3.000 im
  Monat für alle). Ein voller `verify` auf sauberem Arbeitsbaum merkt sich den Commit,
  `tool/release.sh push` setzt danach den Status `werkbank/verify` auf GitHub. Die PR-CI
  beginnt mit einem Job `gate`, der diesen Status für den Kopf des PRs abfragt; ist er da,
  überspringen die teuren Jobs (`needs: gate`, `if: ${{ !cancelled() && needs.gate.outputs.verified != 'true' }}`).
  Ohne Stempel (geändert nach `verify`, gewöhnliches `git push`, `--quick`) läuft alles.
  Prüft die PR-CI eines Projekts nur `verify --quick`, stempelt mit `WB_CI_VERIFY=quick`
  auch der schnelle Lauf.
  Tags gehen genauso: `werkbank push-tag <tag>` (und `werkbank release`) pushen den Tag und
  setzen den Status für den getaggten Commit, wenn `verify` genau ihn geprüft hat; das Gate
  fragt dann `github.sha` ab. Weitere lokale Prüfungen eines Projekts (etwa ein
  Container-Smoke-Test) merken sich ihren Commit mit `wb_stamp <name>`; `push` und `push-tag`
  setzen dafür `werkbank/<name>`, und der passende CI-Job fragt diesen Status ab.
  `workflow_dispatch` prüft immer voll. Das Gate zählt nur Statusmeldungen des
  Repo-Besitzers (ein persönliches Repo); kann es GitHub nicht fragen, prüft die CI voll
  (`!cancelled()`, Fehler der Abfrage gelten als „kein Stempel“). Vorlage für den Job:

  ```yaml
  permissions:
    contents: read
    statuses: read
  jobs:
    gate:
      runs-on: ubuntu-latest
      timeout-minutes: 3
      outputs:
        verified: ${{ steps.stamp.outputs.verified }}
      steps:
        - id: stamp
          env:
            GH_TOKEN: ${{ github.token }}
            SHA: ${{ github.event.pull_request.head.sha || github.sha }}
          run: |
            verified=false
            if [ "$GITHUB_EVENT_NAME" = pull_request ] || [[ "$GITHUB_REF" == refs/tags/* ]]; then
              for _ in 1 2 3; do
                state=$(gh api "repos/$GITHUB_REPOSITORY/commits/$SHA/statuses" \
                  --jq '[.[] | select(.context == "werkbank/verify" and .creator.login == "'"$GITHUB_REPOSITORY_OWNER"'")][0].state // ""' \
                  2>/dev/null || true)
                if [ "$state" = success ]; then verified=true; break; fi
                sleep 10
              done
            fi
            echo "verified=$verified" >> "$GITHUB_OUTPUT"
  ```
- **Ausgaben:** Erzeugtes nach `build/`, Release-Dateien nach `build/release/`, Symbole von
  `--split-debug-info` nach `~/keys/symbols/<app>/<version>/<plattform>/`.

### Release

Ein Release läuft in jedem Projekt gleich, nur die Plattformen unterscheiden sich:

```bash
tool/release.sh release --dry-run     # Plan und Prüfung, ändert nichts
tool/release.sh release [--upload]    # dann wirklich
```

| Phase | Was |
|---|---|
| Vorprüfung | sauberer `main` gleich `origin/main`, Abschnitt `## <version>` im `CHANGELOG.md`, Release-Texte vollständig (bei iOS/Android), dann `verify` (oder Hook `verify_release`) |
| Bauen | je Produkt und Plattform: `android` und `ios` aus der werkbank, andere über `build_<plattform>`; ein Hook `build_<plattform>` ersetzt auch den werkbank-Weg für `android`/`ios` (z. B. Watch-App im IPA, Phone- und Wear-Bundle); ein Produkt mit Hook `release_<produkt>` baut ganz selbst (z. B. per CI) |
| Hochladen | mit `--upload`: Apple über das Xcode-Konto, Play über das Dienstkonto |
| Tag | `<präfix><version>` je Produkt, erst nach Bauen und Hochladen, gepusht |
| GitHub-Release | mit `WB_GH_RELEASE_REPO`: Changelog-Abschnitt als Text, Dateien aus `build/release/` |
| Seiten | `WB_RELEASE_SITES` live (siehe Landingpages) |
| Bericht | `build/release/report-<version>.md`: was passiert ist, was noch von Hand bleibt (Hook `release_manual`) |

Produkte (`WB_PRODUCTS`, Standard `app`) haben je eine Versionsdatei (`WB_VERSION_FILE_<p>`,
Standard `pubspec.yaml`), ein Tag-Präfix (`WB_TAG_PREFIX_<p>`, für die App `WB_APP_TAG_PREFIX`,
sonst `<p>-v`) und Plattformen (`WB_PLATFORMS_<p>`, für die App die vorhandenen Ordner `ios`,
`android`, `macos`). Ein Produkt, dessen Tag es schon gibt, gilt als veröffentlicht und wird
übersprungen. Der Changelog ist die eine Quelle für GitHub-Release, Seite und Store-Texte.

**Swift-Pakete (`Package.resolved`):** Ein Store-Build für iOS oder macOS (`flutter build
ipa|macos`, `xcodebuild archive`) löst die Swift-Pakete neu auf und kann
`ios/**/Package.resolved` und `macos/**/Package.resolved` umschreiben. Dann ist der Checkout
nicht mehr sauber und der nächste Release-Schritt bricht mit „uncommitted changes“ ab.
`werkbank ios` und jeder werkbank-Build in `release` prüfen das gleich danach
(`wb_resolved_guard`) und brechen vor Hochladen und Tag ab. Eigene Apple-Builds eines Projekts
(z. B. `cmd_macos`) und Hooks, die selbst hochladen (`build_<plattform>`, `release_<produkt>`),
rufen `wb_resolved_guard` zwischen Build und Upload auf; die werkbank prüft nach dem Hook nur
noch einmal und kann dann zwar den Tag, aber keinen schon erfolgten Upload mehr verhindern. Dann: die Dateien per PR committen („Swift-Pakete wie beim Store-Build
aufgelöst“) und den Build vom sauberen `main` wiederholen – der Build hat genau diese
Versionen benutzt, sie gehören ins Repo. Die Vorprüfung nennt geänderte `Package.resolved`
eigens; `werkbank resolved` prüft von Hand.

### Changelog

Jedes Projekt führt **`CHANGELOG.md`** (englisch) und **`CHANGELOG.de.md`** (deutsch), Punkt
für Punkt gleich (Sprachen: `WB_CHANGELOG_LANGS`, Standard `en de`). Aus ihm entstehen der
Text des GitHub-Release, die Änderungsseite der Landingpage (per Hugo-Mount, wie bei
Panzergefecht) und die Entwürfe der Store-Texte.

```markdown
# Changelog

Ein, zwei Sätze, was hier steht.

## Unreleased                         ← sammelt während der Arbeit (de: „Unveröffentlicht“)

## 1.9.6 – 2026-11-04                 ← Version ohne Build, ISO-Datum; Build optional: 1.9.6 (29)

### New                               ← de: Neu / Verbessert / Behoben, nur was vorkommt
- Ein Satz je Änderung, aus Sicht der Nutzer
### Improved
### Fixed
```

**Aktualisieren:** Wer etwas für Nutzer Sichtbares mergt, ergänzt es im selben PR unter
`## Unreleased` in beiden Sprachen. Vor dem Release macht `werkbank changelog --draft` daraus
`## <version> – <datum>` (ohne gesammelte Punkte: Entwurf aus den PR-Titeln, mit `ENTWURF`
markiert); das kommt per PR auf `main`. `release` verweigert sich ohne fertigen Abschnitt.

**Formulieren:** Was ändert sich für Nutzer, nicht wie es gebaut ist; keine PR-Nummern,
Klassen oder Dateinamen. Deutsch mit „du“, Englisch im selben Ton. Ein Punkt, ein Satz (zwei,
wenn es nicht anders geht). Erst das Wichtigste. Bibliotheken (Horizont, werkbank) dürfen
technisch schreiben und haben zusätzlich `### Upgrade` mit dem, was beim Wechsel zu tun ist.

### Release-Texte

Zu jedem Store-Build gehören Texte, die zum Upload fertig daliegen:

```
store/ios/testflight/whats_new_<build>_<de-DE|en-US>.txt   „Was testen“ für TestFlight, ≤ 4000 Zeichen, du-Ansprache
store/android/play-notes-<build>.txt                      ein Block je Sprache: <de-DE>…</de-DE>, je ≤ 500 Zeichen
```

`werkbank notes --draft` legt fehlende als Entwurf aus dem Changelog-Abschnitt der Version an
(ohne ihn aus den seit dem letzten App-Tag gemergten PRs), mit der Zeile `ENTWURF`. Solange sie drinsteht,
gilt der Text als fehlend: Die PR-Titel sind englisch und technisch, die Texte schreibt
Claude oder du in Nutzersprache. `werkbank notes` prüft und legt den Play-Block in die
Zwischenablage; `upload-play` nimmt ihn mit.

### Hochladen

- **Apple:** `werkbank upload-apple <archiv>` macht, was „Distribute App“ im Organizer tut,
  mit dem in Xcode angemeldeten Konto – kein API-Schlüssel nötig. Ein zweiter Versuch folgt
  von selbst, falls die Verbindung abbricht.
- **Google Play:** `werkbank upload-play` lädt mit einem Dienstkonto hoch (Play Console →
  Nutzer und Berechtigungen → Dienstkonto einladen, Rechte „Releases verwalten“), Schlüssel
  unter `WB_PLAY_KEY`. Spur `WB_PLAY_TRACK` (Standard `internal`), solange die App nicht
  veröffentlicht ist `WB_PLAY_STATUS=draft`. Nur Python und openssl, kein fastlane.

### Gerätetest

`werkbank devicetest` startet die Integrationstests mit `flutter drive --keep-app-running`
(ohne den Schalter deinstalliert Flutter die App am Ende – samt ihrer Daten) auf allen
angeschlossenen Geräten
(iPhone, iPad, Android, Mac; WLAN-Geräte zählen mit), eins nach dem anderen, und schreibt
`build/devicetest/<zeit>/report.md` mit Ergebnis, Dauer und Log je Lauf. Was ein Gerät
vorher und nachher braucht (App-Daten sichern, App beenden), stehen als Hooks
`devicetest_before`/`devicetest_after` in `werkbank.conf`. Scheitert `devicetest_before`
(etwa weil das gesperrte iPhone keine Sicherung zulässt), läuft auf dem Gerät kein Test.
Ohne Hook beendet ein Mac-Lauf die gestartete App.

## Landingpages

Jede App hat ihre Landingpage in `site/` (Hugo, Horizont als Hugo-Modul, Hugo 0.154.5 wie
in allen Workflows). Bauen, Vorschau und Ausliefern sind überall gleich, nur das Ziel
unterscheidet sich. Die Seiten stehen in `WB_SITES` als `<name>=<ordner>|<baseURL>|<ziel>`:

```bash
tool/release.sh site <name|all>          # Vorschau: baut nach build/site/<ordner>/, ändert nichts
tool/release.sh site <name|all> --live   # ausliefern
```

| Ziel | Ausliefern |
|---|---|
| `blog:<unterordner>` | in den Blog (`regetskcob.github.io/static/<unterordner>/`), Push |
| `ghpages:<owner/repo>[:<domain>]` | gh-pages-Branch des Repos, mit `CNAME` und `.nojekyll`; Ordner in `WB_SITE_KEEP_<name>` bleiben stehen, wenn der Bau sie nicht hat |
| `workflow:<datei>` | startet den Deploy-Workflow des Repos (`gh workflow run`) |
| `hook` | eigene Funktion `site_deploy_<name>` (z. B. FTPS über einen Branch) |

Live geht eine Seite nur über diesen Befehl oder den Release (`WB_RELEASE_SITES`), nicht
bei jedem Push auf `main`. Nacharbeiten nach dem Bau (Weiterleitungen, Extras) stehen in
`site_post_<name>`.

Ziele der Projekte: KNX Monitor `site` → `blog:knx`, `teaser` → `ghpages:regetskcob/KNX-Monitor:knx-monitor.de`;
Jagdaufseher `blog:jagdaufseher`; Panzergefecht `workflow:pages.yaml`; Kalkar kompakt `hook`
(FTPS über das Repo `landing-page`). `werkbank verify` baut alle `WB_SITE_DIRS` zur Prüfung.

## Schlüssel und Geheimnisse

Nie im Repo. Gleiche Namen in allen Projekten:

| Was | Wo |
|---|---|
| Android-Upload-Schlüssel | `~/keys/<name>-upload.jks`, verwiesen aus `android/key.properties` (ignoriert) |
| App Store Connect | `ASC_KEY_ID`, `ASC_ISSUER_ID`, Datei `ASC_KEY_PATH` (Standard `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`) |
| Google Play (Upload) | Dienstkonto-JSON unter `WB_PLAY_KEY` (Standard `~/keys/<app>-play.json`) |
| Build-Werte der App (Supabase, RevenueCat, …) | `~/.config/<app>/<name>.env`, im Projekt mit `wb_env_file` geladen |

## werkbank.conf

`tool/werkbank.conf` ist eine Bash-Datei, die `werkbank` vor jedem Befehl lädt. Alles ist
optional; Vorlage: `werkbank.conf.example` im werkbank-Repo.

| Name | Standard | Wofür |
|---|---|---|
| `WB_APP` | `name` aus `pubspec.yaml` | Dateinamen der Release-Dateien, Symbolordner |
| `WB_TOP_EXTRA` | – | weitere Wurzeleinträge (Regex-Alternativen) |
| `WB_MEDIA_EXTRA` | – | weitere Medienordner (Regex, mit `/` am Ende) |
| `WB_FORMAT_PATHS` | vorhandene von `lib test integration_test test_driver` | Pfade für `dart format` |
| `WB_ANALYZE_ARGS`, `WB_TEST_ARGS` | – | zusätzliche Argumente |
| `WB_SYMBOLS_DIR` | `~/keys/symbols/<app>` | Ziel für Debug-Symbole |
| `WB_SITE_DIRS` | `site`, wenn `site/hugo.toml` da ist | Hugo-Seiten, die `verify` baut |
| `android_args`, `ios_args` | – | Funktionen, die Build-Argumente ausgeben |
| `verify_quick_extra` | – | Funktion mit weiteren Prüfungen, die auch die CI macht (läuft auch bei `--quick`) |
| `WB_APP_TAG_PREFIX` | `v` | Tag-Präfix der App-Releases (Entwürfe der Release-Texte) |
| `WB_STORE_LANGS` | `de-DE en-US` | Sprachen der Release-Texte |
| `WB_PLAY_PACKAGE`, `WB_PLAY_KEY`, `WB_PLAY_TRACK`, `WB_PLAY_STATUS` | –, `~/keys/<app>-play.json`, `internal`, `completed` | Upload zu Google Play |
| `WB_PRODUCTS`, `WB_VERSION_FILE_<p>`, `WB_TAG_PREFIX_<p>`, `WB_PLATFORMS_<p>` | `app`, `pubspec.yaml`, `<p>-v`, Plattformordner | Produkte des Release |
| `WB_CHANGELOG`, `WB_CHANGELOG_LANGS`, `WB_GH_RELEASE_REPO` | `CHANGELOG.md`, `en de`, – | Changelog (weitere Sprachen als `CHANGELOG.<lang>.md`) und Repo der GitHub-Releases |
| `WB_SITES`, `WB_RELEASE_SITES` | – | Seiten und welche der Release live stellt |
| `WB_CI_VERIFY` | `full` | was die PR-CI prüft (`quick`: dann stempelt auch `verify --quick`) |
| `release_<p>`, `build_<plattform>`, `verify_release`, `release_manual`, `site_post_<name>`, `site_deploy_<name>` | – | Hooks des Release und der Seiten |
| `WB_DEVICETEST_TARGETS` | alle `integration_test/*_test.dart` | Tests für `devicetest` |
| `devicetest_before`, `devicetest_after` | – | Funktionen je Gerät (`$1` Geräte-ID, `$2` Plattform) |
| `verify_extra` | – | Funktion mit langsamen Prüfungen (Web-Build, Server, Hugo; nicht bei `--quick`) |

## werkbank aktualisieren

Die werkbank liegt als Kopie in `tool/werkbank/`, damit Projekt und CI ohne Zugang zum
privaten werkbank-Repo laufen. Änderungen entstehen im werkbank-Repo, dann je Projekt:

```bash
~/dev/werkbank/install.sh ~/dev/<projekt>
```

und ein PR im Projekt. `tool/werkbank/VERSION` zeigt, welcher Stand drin ist.
