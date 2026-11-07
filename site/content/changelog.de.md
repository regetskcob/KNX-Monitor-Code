---
title: "Änderungen"
description: "Was die letzten Versionen von KNX Monitor in App, Home-Assistant-Add-on und KNX-Box gebracht haben, neueste zuerst."
layout: "page"
slug: "changelog"
---
Was die letzten Versionen von KNX Monitor gebracht haben, neueste zuerst. App, Home-Assistant-Add-on und KNX-Box haben eine gemeinsame Versionsnummer. Jede Version liegt auf [GitHub](https://github.com/regetskcob/KNX-Monitor/releases); in Home Assistant zeigt das Add-on dieselben Hinweise vor einem Update (auf Englisch).

## 1.9.10 – 7.11.2026

- Vorschau für Tester: jedes Telegramm an MQTT ([#11](https://github.com/regetskcob/KNX-Monitor/issues/11)). Mit der neuen Add-on-Option „Jedes Telegramm an MQTT“ (Docker und Box: `MQTT_TELEGRAMS=true`) geht jedes Gruppentelegramm als JSON an `knx_monitor/telegram/1/2/3`, mit Zeit, Name, DPT, Wert und Einheit aus dem ETS-Projekt. Standard aus. KNX-Secure-Telegramme nur mit eigener Option, höchstens 500 pro Sekunde. Rückmeldung bitte im Issue.
- Home-Assistant-Integration 1.1.0 ([#2](https://github.com/regetskcob/KNX-Monitor/issues/2)): Ereignis-Entitäten, ein Gerätetrigger je Wächter, Bedingungen (Bus verbunden, Aufzeichnung an, Alarm offen, wenig Speicher) und ein Reparaturhinweis, wenn eine sonst regelmäßige Gruppenadresse verstummt. Ohne Supervisor (Home Assistant Container) verbindet sie sich mit KNX-Box oder Docker über einen Kopplungslink mit „Verwalten“.
- KNX-Box übersteht Stromausfälle sauberer ([#4](https://github.com/regetskcob/KNX-Monitor/issues/4)): Ohne Echtzeituhr startet die Uhr beim zuletzt gespeicherten Stand statt beim Datum des ersten Starts, bis dahin wird nichts nach Alter gepackt oder gelöscht. Das Systemprotokoll bleibt, die Neustartliste nennt den Grund.
- Nach einem Absturz zeigt die App einen Hinweis und führt zum Diagnosepaket; „Als Issue melden“ öffnet ein vorausgefülltes Formular nur mit Version, Plattform, Zeit und Art des Absturzes.
- KNX-Box: In den Box-Einstellungen zeigt „Raspberry Pi“ Temperatur, Höchstwert seit dem Start und Warnungen bei Unterspannung oder Drosselung.
- KNX-HAT (kBerry): Der Busmonitor zählt jetzt Rahmen, die das Modul gesehen, aber nicht weitergegeben hat, und die App erklärt es: Der kBerry gibt im Busmonitor etwa jeden zweiten Datenrahmen nicht aus, vollständig zeichnet die Box im Link Layer auf. Wiederanlauf nach Modul-Neustart und 115200 Baud an einer echten Linie getestet.
- Sicherheitsprüfung für Docker: Das UDP-Relais leitet nur KNXnet/IP an Gateway-Adressen weiter, ohne `LAN_ACCESS` hört der Container nur auf localhost (ein Reverse Proxy auf demselben Rechner braucht `LAN_ACCESS=yes`), Verwaltungsrechte gibt es nur mit dem Passwort, „Alle aussperren“ beendet auch Browser-Sitzungen, das erste Passwort braucht 8 Zeichen (`BOX_PASSWORD_FILE` für Docker Secrets), und gekoppelte Geräte können den Verlauf nicht mehr löschen oder den Server blockieren. Die Docker-Vorlage startet jetzt nur lesend (`READ_ONLY=0` zum Senden) und nutzt HTTPS auf Port 8443. Einzelheiten in der Docker-Anleitung.
- KNX-Box und Docker: eigene Anmeldeseite im Browser nur mit Passwort, statt des Browserfensters, das auch nach einem bedeutungslosen Benutzernamen fragte. „Abmelden“ auf der Kopplungsseite beendet die Sitzung, und ist sie abgelaufen, führt die Web-App selbst zurück zur Anmeldung. Apps und Werkzeuge wie curl melden sich weiter wie bisher an.
- Hinweise im Detailblatt eines Telegramms, Befunde, Sicherheitshinweise, Adresse, Name und Produkt im Geräteblatt sowie die Angaben für einen Fehlerbericht lassen sich markieren und kopieren, etwa für eine Frage im Forum.

## 1.9.9 – 6.11.2026

- Docker: `LAN_ACCESS` gilt jetzt bei jedem Start. Ein nachträglich gesetztes `LAN_ACCESS=yes` blieb bisher wirkungslos. Meldungen, Anmeldedialog und Einstellungsseite sprechen vom Zugriff aus dem Netzwerk und vom Passwort statt vom WLAN der Box, das es in Docker nicht gibt.
- Alarme in Add-on und KNX-Box nutzen die Namen, die du in der App korrigiert oder angelernt hast.
- Die Home-Assistant-Mitteilung zu Befunden sagt in Klartext, was los ist, und führt zur Seite des Add-ons.
- Diagnose- und Übergabepakete behalten korrigierte Namen von Gruppenadressen, damit die Aufgaben für die ETS erhalten bleiben.
- Topologie: Geräte mit einer Adresse außerhalb des Projekts, etwa das KNX-Modul einer Box auf der Werksadresse 15.15.255, stehen bei der Linie des Gateways mit Hinweis, statt als eigene Linie mit fehlendem Koppler.

## 1.9.8 – 5.11.2026

- Sicherheit und Tempo: Dieser Version gingen eine gründliche Prüfung aller Teile, ein Angriffstest und ein Lasttest mit 30 Tagen zu je 100.000 Telegrammen voraus.
- Diagramme über 7 und 30 Tage und die Statistik antworten deutlich schneller, auch wenn mehrere gleichzeitig zuschauen. Die Web-App lädt kleiner und beim zweiten Mal aus dem Zwischenspeicher.
- Den Verlauf auf „Aus“ zu stellen löscht ihn: Die App fragt jetzt vorher nach.
- KNX-Box und Docker: Das Box-Passwort lässt sich nur noch mit dem aktuellen Passwort ändern. Beim Koppeln gibt es die Stufe „Nur ansehen“, die nichts auf den Bus schickt. Gekoppelte Geräte sehen nur die aktive Anlage.
- Kopplungslinks von außen zeigen die Adresse und warnen bei unverschlüsselter Verbindung. Eine schon gekoppelte Box wird nur nach Rückfrage ersetzt.
- Namen von Gruppenadressen lassen sich in der App korrigieren und als Importdatei an die ETS zurückgeben.
- CSV-Exporte öffnen sauber in Excel, mit Umlauten, negativen Zahlen und Zeiten mit Zeitzone. Fehlermeldungen sind verständlicher, Löschen fragt nach oder lässt sich rückgängig machen.
- Home-Assistant-Integration 1.0.2: Ihre Dienste stehen nur Administratoren zur Verfügung.

## 1.9.7 – 4.11.2026

- Neu für Home Assistant: die Integration „KNX Monitor“ über HACS ([KNX-Monitor-HA](https://github.com/regetskcob/KNX-Monitor-HA)). Läuft das Add-on, meldet Home Assistant „Neues Gerät gefunden“. Danach gibt es Sensoren und den Schalter für die Aufzeichnung wie beim MQTT-Gerät, Geräte-Auslöser für Wächter, Alarme und die Busverbindung, die Dienste „Bericht erstellen“ und „Verlauf exportieren“, eine Diagnose zum Herunterladen und Reparaturhinweise, wenn der Bus länger weg ist oder der Speicher voll. Ein MQTT-Broker ist dafür nicht nötig.

## 1.9.6 – 4.11.2026

- Diagramme: Neben „Geladen“ gibt es jetzt „Heute“, „7 Tage“ und „30 Tage“ aus der dauerhaften Aufzeichnung von Add-on und KNX-Box. Ein Klick setzt das Fadenkreuz und bietet genau dort „Hier kommentieren“ an; der Kommentar hält den vorherigen und den aktuellen Wert jeder Linie fest.
- Übersicht: Alle Karten mit Werteverlauf zeigen ihn wieder, Schaltzustände wie Fenster und Licht als Blöcke für „Ein“. Die Verläufe zeichnen seltener neu.
- Beim Überfahren der Aktivitätsleiste siehst du, zu welcher Zeit der Balken gehört. Die Ursachenkette nennt die Ankunftszeit des Telegramms.
- Kommentare erscheinen auf iPad, Mac und im Browser als richtiger Dialog statt als schmaler Hinweis.
- Home-Assistant-Add-on: Läuft die Verbindung über die KNX-Integration, füllt das Add-on Lücken aus deren Telegrammspeicher (ab Home Assistant 2026.7). Nach der Installation siehst du also gleich, was Home Assistant schon aufgezeichnet hat, und ein Update reißt kein Loch mehr.
- Der ganze Verlauf lässt sich als ZIP mit einer ETS-Datei pro Tag exportieren, SpectrumKNX liest ihn in einem Rutsch ein. Auch auf der KNX-Box.

## 1.9.5 – 3.11.2026

- Der Verlauf von Add-on und KNX-Box lässt sich als Gruppenmonitor-Datei der ETS herunterladen. Dasselbe Format nutzen der Telegrammspeicher von Home Assistant und SpectrumKNX.
- Aufnahmen importieren liest jetzt auch Dateien aus Home Assistant, SpectrumKNX, der ETS 6, von Gira-Loggern und Node-RED knx-ultimate.
- Home Assistant: Das MQTT-Gerät „KNX Monitor“ liefert Buslast, offene Alarme, Verfügbarkeit der letzten 24 Stunden und den freien Speicher, dazu zwei neue Blueprints.

## 1.9.4 – 3.11.2026

- KNX Monitor ist Open Source unter der GPLv3: [KNX-Monitor-Code](https://github.com/regetskcob/KNX-Monitor-Code). Alles, was der Server auf den Bus schickt, läuft durch eine einzige Datei.
- Neue Option „Nur lesen“ im Add-on, von Anfang an eingeschaltet: Der Server sendet nichts auf den Bus, auch keine Leseanfragen. Aufzeichnung und Auswertung laufen weiter. Docker und KNX-Box haben dasselbe als Schalter.
- Im dunklen Modus haben Umrisse etwas mehr Kontrast.

## 1.9.3 – 2.11.2026

- Neue Oberfläche: ein grüner Statuskasten über Übersicht, Details und Live, Karten im Raster, ein Schreiben-Knopf oben und eine Live-Liste, die mit Adresse und Namen beginnt.
- Das Menü ist nach Aufgaben sortiert, mit Symbolen; Auswertungen stehen für sich.
- Die Kommunikationskarte zeigt Geräte in Ebenen und Zoomstufen, Topologie und Projekt-Abgleich öffnen schneller.
- Konten gibt es vorerst nicht mehr: Die App meldet nichts mehr an und spricht mit keinem Kontodienst. Deine Daten auf dem Gerät bleiben, wie sie sind.

## 1.9.2 – 1.11.2026

- Neu für alle, die planen oder bauen: der Hausplan, ganz ohne Gateway, im Home-Assistant-Add-on, im Browser der KNX-Box und in der Linux-App. Du gehst deinen Alltag durch, daraus entstehen Raumbuch und Grundriss fürs Gespräch mit dem Fachbetrieb. Leuchten und Steckdosen legst du als schaltbar, dimmbar oder mit Dauerstrom fest, die App rechnet den Kanalbedarf aus und gibt die Geräteliste als CSV und PDF aus. Dazu kommen alle Ebenen samt Außenbereich, Prüfungen wie der Taster im Türaufschlag, Fristen je Bauart, Angebots-Check, PDF mit Maßen und DXF. Der Katalog ist nach bestem Wissen zusammengestellt und ersetzt keine Elektroplanung.
- Vor dem Schreiben auf den Bus erscheint ein Hinweis, dass das ein Eingriff in die Anlage ist. Du kannst ihn ausblenden und auf der Startseite wieder einschalten; das Ausblenden steht mit Datum im Diagnosepaket.
- Sicherheit in den Apps: Kopplungslinks warnen bei fremden Adressen, Sicherungen enthalten keine Kauf-Schlüssel mehr, die Verschlüsselung ist rund zehnmal schneller.
- KNX-Box und Add-on: HTTPS, Pflichtwechsel des Passworts vom Aufkleber, getrennte Rollen und mehr Schutz gegen kaputte Telegramme und volle Datenträger.
- Bedienung: Am Telefon macht die Suche Platz, die Tastatur passt zum Feld und schließt beim Scrollen. Am Mac, unter Windows und am iPad mit Tastatur gibt es Kürzel und ein Menü per Rechtsklick auf Telegramme.

## 1.9.1 – 31.10.2026

- Deine Daten: Die Apps verschlüsseln ihre Dateien jetzt mit AES-256-GCM, der Schlüssel liegt im Schlüsselbund des Systems. Ohne nutzbaren Schlüsselbund (Linux ohne libsecret) bleiben sie unverschlüsselt, Einstellungen wie das Gateway ebenfalls.
- App-Sperre auf Wunsch: Face ID, Fingerabdruck, Windows Hello, Gerätecode oder App-Passwort samt Notfallschlüssel als PDF.
- Sicherung: alles von diesem Gerät in eine Datei mit eigenem Passwort, in den Apps, Format offen beschrieben.
- Diagnosepaket: Bildschirmfotos gehen nur noch mit, wenn du sie einschaltest.
- Fotos des Verteilers und Etiketten mit QR-Code je Anlage.
- Konto (freiwillig): Zwei-Faktor-Anmeldung, Export der Kontodaten, ein entferntes Gerät verliert seine Sitzung auf dem Server.
- KNX-Box und Add-on: Eine Aufzeichnung ohne bekannte Uhrzeit bleibt nach einem Neustart sichtbar und läuft nach der Aufbewahrung ab wie jeder andere Tag. Springt die Uhr beim Packen, wird kein Tag mehr überschrieben. Projekt und Keyring werden beim Wiederverbinden geprüft. Die Passwortprüfung hält Server und Aufzeichnung nicht mehr auf. Das Beenden hängt nicht mehr an einem KNX-HAT, der nicht antwortet.

## 1.9.0 – 29.10.2026

- Für Einsteiger: Die Anlage lässt sich jetzt ganz ohne ETS-Projekt anlernen – Taster drücken, benennen, fertig; daraus entsteht ein eigenes Projekt. Ohne Expertenmodus zeigt die Live-Liste jedes Telegramm als Satz („Taster Flur hat Küchenlicht eingeschaltet“).
- Neu: Verbindungshilfe, die Schritt für Schritt erklärt, warum das Gateway nicht antwortet; eine Ampel auf der Startseite mit Wochenbericht; „KNX lernen“ mit kurzen Lektionen.
- Ursachenkette und Reaktionszeiten: was ein Telegramm ausgelöst hat und wie schnell die Rückmeldung kam, ohne Expertenmodus in denselben Sätzen wie die Live-Liste.
- Home Assistant: Die erzeugte KNX-Konfiguration schlägt auf Wunsch auch Geräte vor. Dazu Sicherheits-Check, Geräteinventar (Hersteller, Seriennummer, Firmware) und ein Forenpaket mit allen Angaben für eine Frage im Forum.
- Projekt-Abgleich mit neuen Prüfregeln: mehrere Leseantworten, Adressen ohne Sender oder Empfänger, volle Linien, ungefilterte Hauptgruppen 14/15, Adressen ohne Namen oder Datentyp und Zentral-Aus/Ein. „Aufgaben für die ETS“ sammelt alles als Liste und PDF, die Gruppenadressen auch als ETS-Import (Vorschau).
- Für Elektriker: Durchklingeln mit Klangquittung (jeder Taster quittiert hörbar, vorher ein Testton: „Gehört? Dann kann’s losgehen.“), Abnahmeprotokoll mit Unterschrift auf dem Gerät und Fehlerjagd, die mit der KNX-Box sporadische Fehler über Tage fängt.
- Dashboard: Diagramm-Karten mit Vorlagen und Bus-Kennzahlen, Vorlagen lassen sich teilen.
- Aktoren ohne Herstellergrafik haben jetzt eine neutrale Frontansicht mit Kanälen, Beschriftungsfeldern und Busklemme.
- Ausfallsicherheit: Die App startet auch mit beschädigten Einstellungen oder Anlagendateien und stellt sie aus Sicherungen wieder her. Die KNX-Box behält beim Update die alte Version und springt zurück, wenn die neue nicht startet.
- Home-Assistant-Add-on und KNX-Box: Ein Verbindungsversuch mit einem anderen Gateway stellt Daueraufzeichnung und Fehlerjagd erst um, wenn die neue Verbindung steht. Die Verbindungshilfe erscheint jetzt auch dort.
- KNX-Box (Vorschau): Boden für die Hutschiene mit angeschraubtem Federclip; empfohlen ist Variante 1.

## 1.8.4 – 26.10.2026

- KNX-Box (Vorschau): Die Box kann sich jetzt über das Aufsteckmodul kBerry von Weinzierl direkt mit der KNX-Linie verbinden, ohne KNX/IP-Gateway. Als Verbindungsart „KNX-HAT (kBerry)“ wählen (Expertenmodus); ein Busmonitor-Modus mit Quittungen ist auch dabei.
- KNX-Box: Der Browser fragt nicht mehr bei jedem „Verbinden“ erneut nach dem Passwort, und der Monitor öffnet jetzt auch in Safari und auf iPad und iPhone. Beim Anmelden geht jeder Benutzername, es zählt nur das Passwort der Box.
- KNX-Box: Die Box startet jetzt auch ohne USB-SSD (die Daten bleiben dann auf der SD-Karte), und mit hinterlegtem SSH-Schlüssel darf das Wartungskonto sudo nutzen.
- KNX-Box: Die Verbindungstexte auf der Box sagen „Box“ statt „Add-on“.

## 1.8.3 – 25.10.2026

- Neue Einführung auf dem Verbinden-Bildschirm: drei Kapitel (Grundlagen, Auswerten, Expertenmodus) mit echten Ansichten im Demo-Haus. Im Add-on und auf der KNX-Box laufen alle drei am Stück, und die letzte Karte öffnet das Demo-Haus. Der Knopf hebt sich ab, solange ein Kapitel ungesehen ist.
- Geräteblatt: Die Aktionsknöpfe brechen auf schmalen Telefonen nicht mehr um; sie stehen nebeneinander, solange sie passen, sonst untereinander.
- KNX-Box (Vorschau): Das druckbare Gehäuse gibt es jetzt als eine schlanke Variante für Pi 3B bis 5 mit kBerry, mit Modulbrücke, USB-Abdeckung, optionalem Sockel für die Hutschiene und Probedrucken für die Gewindeeinsätze und den Deckel. Gedruckt wird mit 0,2 mm Schichthöhe.

## 1.8.2 – 25.10.2026

- KNX-Box (Vorschau): vorbereitet für den direkten Anschluss an die KNX-Linie mit dem Aufsteckmodul KNX BAOS 838 kBerry von Weinzierl für den Raspberry Pi. Das Image gibt die serielle Schnittstelle für das Modul frei, und die Box-Einstellungen in der App können es testen: Antwort, unterstützte Modi, Telegramme und ein Busmonitor mit Quittungen. Aufgezeichnet wird vorerst weiter über IP.
- Die Box-Seite hat eine Anleitung für Bastler und ein druckbares Gehäuse mit einer Variante für den kBerry (beides Vorschau, noch nicht an echter Hardware getestet).

## 1.8.1 – 25.10.2026

- KNX Monitor läuft auch als Docker-Container ohne Home Assistant (etwa neben ioBroker, auf einem NAS oder unter Proxmox): ein Image für amd64 und arm64, `ghcr.io/regetskcob/knx-monitor`, mit Passwort und optional MQTT.
- MQTT: Jeder Wert erscheint zusätzlich als eigenes Topic, und der Broker lässt sich außerhalb von Home Assistant über Umgebungsvariablen einstellen.

## 1.8.0 – 25.10.2026

- Automationen: Das Add-on löst die Ereignisse `knx_monitor_watcher`, `knx_monitor_alarm` und `knx_monitor_bus` aus, auch ohne offenen Browser. Drei Blueprints zum Import mit einem Klick sind in der Dokumentation verlinkt.
- Mit einem MQTT-Broker (Mosquitto) erscheint das Add-on als Gerät „KNX Monitor“: Bus verbunden, Schalter für die Aufzeichnung, Telegramme pro Minute und heute, Wiederholungen, letztes Telegramm, Ereignis-Entitäten und Gerätetrigger für jeden Wächter und für Alarme und Störungen.
- Neue Optionen `alarm_notifications` und `watcher_notifications`: schalten die Mitteilungen ab, wenn du über eigene Automationen benachrichtigst.
- Ist die KNX-Integration eingerichtet, schlägt das Add-on vor, ihre Verbindung mitzunutzen, statt einen eigenen Tunnel zu belegen.
- Das Menü zeigt die Version von App und Add-on; Diagnosepakete enthalten Add-on-Version, Bildschirmgröße und Zeitzone.

## 1.7.9 – 24.10.2026

- Nach einem Verbindungsabbruch, etwa wenn die Home-Assistant-App im Hintergrund war, holt die Ansicht die verpassten Telegramme aus der Aufzeichnung, statt direkt hinter den alten weiterzumachen.
- Aktivitätsleiste „Heute“: Der Rest des Tages ist eine schlichte Linie, statt wie eine Lücke in der Aufzeichnung auszusehen.
- Details: Der Verlauf zeigt die letzten 40 Werte; im Vollbild alle, zum Scrollen.

## 1.7.8 – 23.10.2026

- Behoben: Die Add-on-Seite blieb seit 1.7.1 leer. Sie startet wieder, ebenso die Webseite der KNX-Box.
- Statistik: Lastspitzen und Zellen der Heatmap filtern den Monitor nach Zeit (neuer Filterbegriff `zeit:`, z. B. `zeit:14:05-14:10`); auf Englisch heißt der Absenderfilter `from:`.
- Die Gesundheitsprüfung zeigt beim Einlesen ihren Fortschritt und neben „Jetzt prüfen“ die voraussichtliche Dauer.
- Übersicht ohne ETS-Projekt: Erratene Datums- und Zeitwerte stehen groß da, die Rohbytes klein darunter.
- Lange Werte im Verlauf brechen um, statt aus den Details zu laufen.

## 1.7.7 – 23.10.2026

- KNX-Box: Das Druckblatt hat zwei gleich große Aufkleber, Aufkleber 1 für die App oben auf die Box und Aufkleber 2 mit dem WLAN unten drauf.

## 1.7.6 – 23.10.2026

- KNX-Box: Nach dem ersten Start liegt auf der SD-Karte je Sprache ein Druckblatt mit dem Aufkleber zum Ausschneiden, WLAN-Code, Passwörtern, dem Link zur Linux-App und den nächsten Schritten.

## 1.7.5 – 23.10.2026

- Kommentare an Telegrammen, Diagrammen und Aufnahmen, mit bis zu drei Bildschirmfotos. Telegrammlisten markieren kommentierte Adressen; alle Kommentare stehen unter Werkzeuge › Kommentare.
- Zeitleiste für Aufnahmen: eine Spur je Gruppenadresse, ziehen und zoomen, ein Tipp auf ein Telegramm kommentiert es.
- „Fehler melden“: Aufnahme starten, den Fehler nachstellen, jedes Mal „Jetzt ist es passiert“ tippen und das Diagnosepaket an deinen Elektriker schicken.
- Ein geöffnetes Diagnosepaket zeigt Befunde: das Problem mit Bildschirmfotos, automatische Hinweise (Verbindung, Secure, Wiederholungen, unbeantwortete Lesungen, Ausfälle), Kommentare und die aktivsten Adressen.
- Eine Seite für alle Exporte: Telegramme als PDF, CSV oder ETS-Datei, Berichte (Busstatistik, Gesundheitsprüfung, Inbetriebnahmeprotokoll), ein gemeinsames ZIP und die letzten Exporte zum erneuten Teilen.
- PDFs entstehen im Hintergrund und teilen lange Tabellen auf Seiten auf; große Gesundheitsberichte frieren die App nicht mehr ein.
- KNX-Box: ab Werk nur im eigenen WLAN erreichbar; der Zugang über das Netzwerkkabel lässt sich in der App einschalten.

## 1.7.3 – 22.10.2026

- Das Add-on verlinkt seine Website knx-monitor.de mit Support, Datenschutzerklärung und FAQ.

## 1.7.2 – 22.10.2026

- Aktoren aller Hersteller nutzen wieder die eigene Zeichnung der App. Gerätegrafiken, die nur zum Testen gedacht waren, sind nicht mehr enthalten.

## 1.7.1 – 22.10.2026

- Topologie und die Details zu Geräten, Kopplern und Aktoren brauchen im Add-on viel weniger CPU: keine Animationen, Zeichnungen aktualisieren höchstens einmal pro Sekunde.
- Das Diagnosepaket enthält die ganze Sitzung statt der letzten 5.000 angezeigten Telegramme und kann Tage aus dem Langzeitverlauf als Quelle nutzen.
- Diagrammkacheln zeigen Werte über die Zeit wie das Diagramm im Vollbild, Ein/Aus-Werte als schmale Bänder.
- Dialoge, Favoriten und Pins wirken klarer; die Web-App startet in den Farben des Startbildschirms.

## 1.7.0 – 21.10.2026

- Wächter laufen im Add-on: Sie arbeiten auch ohne offenen Browser weiter und schicken eine Mitteilung in Home Assistant (auch als Push mit `notify_service`). Wächter liegen im Add-on, alle Browser teilen sie.
- Der Busmonitor funktioniert neben dem Add-on: Das Add-on gibt seinen Tunnel ab, solange der Busmonitor offen ist (vorher meldete das Gateway keine freien Tunnel).
- Wer das Panel von KNX Monitor verlässt und zurückkommt, behält die letzten Werte und Telegramme, statt leer anzufangen.
- Der Import des ETS-Projekts zeigt seinen Fortschritt und öffnet passwortgeschützte ETS5-Projekte schneller.
- Die Topologie bleibt auch bei langen Aufnahmen flüssig.
- Diagramme: Ein/Aus-Werte bekommen eine eigene Zeile; Diagramme lassen sich mit Projektadressen vorbereiten, die noch nichts gesendet haben; „Freie Auswahl“ entfällt.
- Die Projektprüfung nutzt auf breiten Bildschirmen zwei Spalten.
- Die Seitenleiste beginnt mit der Übersicht.

## 1.6.0 – 21.10.2026

- Topologie: Linien, Koppler und Geräte als Baum mit Detailbereich. Linienkoppler, Netzteile, Aktoren, Taster, Präsenzmelder, Wetterstationen und Rauchmelder sind gezeichnet wie die echten Geräte, mit Status-LEDs und Telegramm-Pulsen auf der Busleitung.
- Schaltobjekte lassen sich direkt aus der Objektliste und der Topologie mit 0/1 senden.
- Der Projekt-Import liest die Flags der Kommunikationsobjekte (K L S Ü A); der Projekt-Abgleich vergleicht das ETS-Projekt auch ganz ohne Busverkehr.
- Werte ohne Projekt: 3- und 8-Byte-Werte erscheinen als Datum und Uhrzeit.
- Diagnosepaket für den Support: Fehlerbericht, Aufnahme, Projekt und technische Angaben als ZIP, ohne persönliche Daten.
- Daten liegen jetzt je Anlage; vorhandene Daten ziehen beim Start in die erste Anlage um.

## 1.5.1 – 19.10.2026

- Sicherheit im Add-on: Die Busverbindung mit den IP-Secure-Passwörtern und die Zugangsdaten der KNX-Box sind über den Dateispeicher des Add-ons nicht mehr erreichbar.

## 1.5.0 – 19.10.2026

- Neues Aussehen mit Horizont, dem Design-System aller meiner Projekte. In Home Assistant übernimmt das Add-on die neutralen Farben von Home Assistant, Akzent, Schrift und Linien bleiben.
- Neues Symbol: eine Busklemme auf der grünen Busleitung.
- Werte, Adressen und Zeiten in einer Schrift mit fester Breite; jeder Status hat ein Zeichen und ein Wort, nicht nur eine Farbe.
- Aufnahmen: Langes Drücken auf Aufnehmen behält die letzten 10 Sekunden. Vor einer Wiedergabe lassen sich Werte ändern und Telegramme entfernen.
- Diagramme werden je Anlage gespeichert und erscheinen als eigene Sektion in der Übersicht.
- Ab 600 px ist das Menü eine Seitenleiste.

## 1.4.0 – 18.10.2026

- Schnellfilter wie „Unbeantwortet“ wirken jetzt auch in Übersicht und Objekten.
- Raumnummern wie „OG K1“ in ETS-Namen werden erkannt, Objekte landen im richtigen Raum.
- Sichereres Speichern: Ein abgebrochener Schreibvorgang hinterlässt keine leere Datei mehr.

## 1.3.0 – 17.10.2026

- Neu im Add-on: die dauerhafte Aufzeichnung. Das Add-on hält selbst eine Busverbindung offen, auch ohne offenen Browser, verbindet sich nach Aussetzern sofort neu und schreibt den Verlauf. Alle offenen Ansichten teilen sich diesen einen Tunnel.
- Verbindungsarten: Tunnel über UDP oder TCP, feste Tunneladresse, KNXnet/IP-Routing, KNX IP Secure und ein Home-Assistant-Modus, der die Telegramme der KNX-Integration ohne eigenen Tunnel mitliest.
- KNX Data Secure: Keyring aus der ETS importieren, gesicherte Telegramme werden live und in der Aufnahme entschlüsselt.
- Alarm-Mitteilungen kommen jetzt vom Add-on selbst, Langzeitstatistik mit Aktivitäts-Heatmap.

## 1.2.0 – 17.10.2026

- Neu: Werkzeug „Gesundheit“. Es liest bekannte Status-Adressen, meldet verstummte Adressen, überwacht Zyklen, prüft Plausibilität, Datentyp je Absender und Busqualität.
- Neu: Inbetriebnahme-Checkliste mit Notizen und PDF-Protokoll.
- Die Kommunikationskarte startet mit einer Übersicht aller Adressen und Geräte.
- Sender und Empfänger aus dem ETS-Projekt anhand der Flags; Tunneladressen getrennt in der Topologie.
- Das Add-on kommt als fertiges Image für amd64 und aarch64.

## 1.1.0 – 15.10.2026

- Alarm-Mitteilungen über Home Assistant, Busmonitor mit allen Frames samt Quittungen, Topologie mit Linien und Kopplern.

## 1.0.0 – 14.10.2026

Der erste Tag: An einem Tag entstand aus einer Idee die erste Fassung der App, und am Abend lief sie schon als Add-on in der Seitenleiste von Home Assistant.

- Verbindung per KNXnet/IP-Tunnel, Gruppenmonitor live, Werte schreiben.
- Gruppenadressen aus der ETS als CSV oder direkt aus der Projektdatei (.knxproj), PDF-Export ausgewählter Telegramme.
- Übersicht nach Räumen und Objekten, Verlaufsdiagramme, Aufnahmen mit Wiedergabe und Trigger-Aufnahme mit Vor- und Nachlauf.
- Diagnose: Status lesen, Programmiermodus finden, Adressen prüfen, Geräteinfo, Linienscan, Kommunikationskarte, Statistik und Projekt-Abgleich.
- Deutsch und Englisch, iPhone, iPad, Mac und Home-Assistant-Add-on.
