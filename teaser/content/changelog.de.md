---
title: "Änderungen"
description: "Was die letzten Versionen von KNX Monitor in App, Home-Assistant-Add-on und KNX-Box gebracht haben, neueste zuerst."
layout: "page"
slug: "changelog"
---
Was die letzten Versionen von KNX Monitor gebracht haben, neueste zuerst. App, Home-Assistant-Add-on und KNX-Box haben eine gemeinsame Versionsnummer. Jede Version liegt auf [GitHub](https://github.com/regetskcob/KNX-Monitor/releases); in Home Assistant zeigt das Add-on dieselben Hinweise vor einem Update (auf Englisch).

## 1.9.3 – in Vorbereitung

- Konten gibt es vorerst nicht mehr: Die App meldet nichts mehr an und spricht mit keinem Kontodienst. Deine Daten auf dem Gerät bleiben, wie sie sind.

## 1.9.2 – 1.11.2026

- Neu für alle, die planen oder bauen: der Hausplan, ganz ohne Gateway. Du gehst deinen Alltag durch, daraus entstehen Raumbuch und Grundriss fürs Gespräch mit dem Fachbetrieb. Leuchten und Steckdosen legst du als schaltbar, dimmbar oder mit Dauerstrom fest, die App rechnet den Kanalbedarf aus und gibt die Geräteliste als CSV und PDF aus.
- Mit Plus: alle Ebenen samt Außenbereich, Prüfungen wie der Taster im Türaufschlag, Fristen je Bauart, Angebots-Check, PDF mit Maßen und DXF. Der Katalog ist nach bestem Wissen zusammengestellt und ersetzt keine Elektroplanung.
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
