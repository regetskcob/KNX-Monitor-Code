---
title: "Feedback"
description: "Fehler melden und Fragen zu deiner Anlage stellen, ohne dein ETS-Projekt hochzuladen: mit dem Diagnosepaket aus KNX Monitor."
layout: "page"
---
Für Fehler und Fragen zu deiner Anlage brauchen wir oft deine Gruppenadressen und Details aus dem ETS-Projekt. Bitte lade dafür nicht dein Projekt hoch und schick uns kein Passwort: Eine `.knxproj`-Datei enthält mehr, als wir brauchen, und Foren und GitHub-Issues sind öffentlich. Dafür gibt es das **Diagnosepaket**.

## Das Diagnosepaket

Eine ZIP-Datei, die KNX Monitor für dich zusammenstellt. Du siehst vor dem Senden genau, was drin ist („Dateiinhalt ansehen“).

**Enthalten:** die Busaufzeichnung um den Fehler, aus dem Projekt die Gruppenadressen, Datenpunkttypen, Geräte und Verknüpfungen, deine Beschreibung, deine Kommentare, die letzten Meldungen der App und technische Eckdaten: App- und Add-on-Version, Plattform, Betriebssystem bzw. Browser, Verbindungsart, Typ und Name des Gateways.

**Nicht enthalten:** die ETS-Projektdatei und ihr Passwort, Keyring und Schlüssel sowie Passwörter. Data-Secure-Telegramme stehen nur mit Zeit und Adressen drin, ohne Inhalt.

**Gefiltert, soweit erkennbar:** IP-Adressen, Hostnamen, MAC- und Seriennummern, E-Mail-Adressen und bekannte Namen von Projekt, Installation und Kunde; Projekt- und Installationsname werden durch Platzhalter ersetzt. **Ganz sicher ist das nicht:** Namen, die du selbst eintippst oder die in Gruppenadressen stehen, erkennt der Filter nicht, und Telegrammwerte können zeigen, wann jemand zu Hause ist. Lies das Paket deshalb vor dem Senden kurz durch.

**Bildschirmfotos** gehen nur mit, wenn du das einschaltest; ab Werk ist es aus. Sie werden nicht gefiltert, alles darauf Sichtbare kommt bei uns an.

**Namen:** Ob die Namen deiner Gruppenadressen und Geräte mitgehen, entscheidest du mit dem Schalter „Namen mitsenden“. Sie helfen uns sehr, ohne sie stehen dort nur Adressen und Produkte.

{{< diag-names >}}

**Störungsmeldung an den Elektriker:** Sie ist etwas anderes als das Diagnosepaket für uns. Dort gehen die Namen und die Bildschirmfotos an deinen Kommentaren mit, ohne Schalter. Hänge also nur an, was der Empfänger sehen darf.

## So erstellst du es

1. KNX Monitor öffnen (App oder Home-Assistant-Add-on), mit dem Bus verbinden, das ETS-Projekt geladen.
2. **Tritt der Fehler noch auf?** Unter Werkzeuge › Problem melden die Aufzeichnung starten, den Fehler nachstellen und jedes Mal „Es ist gerade passiert“ antippen. Danach entsteht das Paket ab dem Start.
3. **Sonst** unter Werkzeuge › Diagnosepaket beschreiben, was passiert ist, den Zeitraum um den Fehler wählen und festlegen, ob Namen mitgehen.
4. „Paket teilen“, „Paket speichern“ oder im Browser „Paket herunterladen“.

## Wohin damit

**Per E-Mail an [support@knx-monitor.de](mailto:support@knx-monitor.de)**, mit ein, zwei Sätzen, worum es geht. Das Paket bleibt bei uns und wird nicht veröffentlicht.

Schreibst du in einem Forum oder in einem [GitHub-Issue](https://github.com/regetskcob/KNX-Monitor/issues), genügt dort der Hinweis „Diagnosepaket per E-Mail geschickt“. Bitte häng das Paket dort nicht an: Beides ist öffentlich.

Wir öffnen das Paket in KNX Monitor, stellen den Fehler nach und nutzen es nur dafür. Sobald deine Anfrage erledigt ist, löschen wir es. Mehr dazu im [Datenschutz](/datenschutz/).

## Noch ohne KNX Monitor?

Geht es nur um den Import, etwa weil dein Projekt nicht geladen wird, hilft uns oft schon der Export der Gruppenadressen als CSV aus der ETS (Gruppenadressen › Export). Er enthält kein Passwort.

## Ideen und Wünsche

Neue Funktionen sammeln wir öffentlich in den [GitHub-Issues](https://github.com/regetskcob/KNX-Monitor/issues). Stimm dort mit 👍 für das ab, was du brauchst, oder leg ein neues Issue an.
