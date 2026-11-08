---
title: "Datenschutzerklärung"
description: "Datenschutzerklärung für die App Busclear, das Home-Assistant-Add-on und diese Website. Kurz: kein Tracking, Anlagendaten bleiben lokal, kein Konto."
---

<p class="t-kennung hz-kennung">Stand: November 2026</p>

> **Kurz gesagt:** Wir erheben so wenig wie möglich: kein Konto, keine Analyse, kein Tracking. Alles, was die App über deine Anlage verarbeitet, bleibt auf deinem Gerät bzw. deiner Busclear Box, außer du teilst es selbst. Ab Version 1.9.1 verschlüsseln die Apps ihre Dateien, und du kannst sie sperren und selbst sichern, jeweils mit den unten genannten Grenzen. Ausnahmen: In den Store-Versionen fragt die App beim Start RevenueCat nach deinem Stand, auch wenn du nichts gekauft hast; und unter Android sendet der QR-Scanner (Google ML Kit) technische Diagnosedaten an Google, siehe unten.

## Verantwortlicher

Verantwortlich im Sinne der DSGVO ist der im [Impressum](https://www.regetskcob.de/legal/) genannte Anbieter.

## Die App (iPhone, iPad, Android, Desktop)

### Keine Datenerhebung durch uns

Die App sendet keine Daten an uns. Sie enthält keine Werbe- oder Tracking-Bibliotheken und benötigt kein Konto. Server betreiben wir für die App nicht.

### Was lokal auf deinem Gerät gespeichert wird

- Verbindungseinstellungen deiner KNX-Schnittstelle (IP-Adresse, Port)
- Aus deinem ETS-Projekt oder CSV-Export gelesene Daten: Gruppenadressen, Namen, Datenpunkttypen, Geräte, Räume, Verknüpfungen
- Mitgeschnittene Telegramme, Aufnahmen, Langzeitverlauf, Prüfergebnisse (Gesundheit, Inbetriebnahme), deine Notizen und Kommentare samt Bildschirmfotos, Fotos des Verteilers
- App-Einstellungen wie Sprache, Favoriten und Benachrichtigungsregeln
- Die letzten Meldungen der App (bis zu 300 Zeilen) in einer Datei auf dem Gerät, damit sie einen Absturz überleben. Sie verlassen das Gerät nur, wenn du ein Diagnosepaket teilst
- Bei KNX Secure: die aus dem Keyring gelesenen Schlüssel und Tunnel-Passwörter, damit die App sich erneut verbinden und Telegramme entschlüsseln kann. Sie liegen im Schlüsselbund des Systems (iOS/macOS-Schlüsselbund, Android Keystore, Windows bzw. Linux-Schlüsselbund), nur auf diesem Gerät, außer du legst sie auf deine Busclear Box oder in eine eigene Sicherung. Ein von Hand eingegebenes Tunnel-Passwort wird nicht gespeichert.

Das Passwort eines geschützten ETS-Projekts und das Passwort des Keyrings werden nur zum Entschlüsseln beim Import verwendet und nicht gespeichert. Du kannst alle Daten jederzeit in der App löschen oder die App deinstallieren; dabei werden die Daten vom Gerät entfernt.

### Verschlüsselung auf dem Gerät (ab Version 1.9.1)

Die Apps auf iPhone, iPad, Android, Mac, Windows und Linux verschlüsseln ihre Dateien, also Anlagen, Projekte, Verlauf, Aufnahmen, Kommentare und Fotos, mit AES-256-GCM. Der Schlüssel ist zufällig und liegt im Schlüsselbund des Systems. Das schützt, wenn jemand den Datenträger ausbaut oder ein anderes Benutzerkonto nutzt. Die Grenzen:

- Ohne nutzbaren Schlüsselbund (Linux ohne libsecret) bleiben die Dateien unverschlüsselt.
- Einstellungen wie Gateway und Benutzername sind nicht verschlüsselt. Was du exportierst und teilst, ist danach ebenfalls nicht mehr geschützt.
- Programme und Personen, die unter deinem entsperrten Benutzerkonto laufen, kann das nicht zuverlässig aufhalten.
- Auf iPhone und iPad können Dateien und Dateischlüssel Teil deiner eigenen verschlüsselten Gerätesicherung sein, sonst wären sie nach einem Gerätewechsel verloren. Die Secure-Schlüssel bleiben auf dem Gerät. Unter Android sind die App-Daten von der Systemsicherung ausgenommen.

### App-Sperre (ab Version 1.9.1, freiwillig)

Auf Wunsch fragt die App beim Start und nach einer von dir gewählten Zeit im Hintergrund nach Face ID, Fingerabdruck, Windows Hello oder dem Gerätecode, oder nach einem eigenen App-Passwort; unter Linux gibt es nur das Passwort. Biometrische Daten sieht die App nicht, die Prüfung macht dein System. Das App-Passwort speichern wir nicht im Klartext und kennen es nicht; zum Passwort erstellt die App einen Notfallschlüssel als PDF, den du getrennt vom Gerät aufbewahrst. Ohne beide bleibt nur, die Daten der App auf diesem Gerät zu löschen. Die Sperre schützt vor jemandem, der das Gerät in der Hand hat, nicht vor Schadsoftware unter deinem Benutzerkonto. Der Bus läuft währenddessen weiter, Alarme melden sich weiter.

### Sicherung (ab Version 1.9.1)

In den Apps speicherst du alles von diesem Gerät in eine Datei mit eigenem Passwort (mindestens 12 Zeichen), in jeder Stufe und kostenlos: Anlagen, Projekte, Keyrings, Kommentare, Aufnahmen, Verlauf und Einstellungen. Die Datei entsteht nur, wenn du das auslöst, und liegt, wo du sie ablegst. Wir bekommen sie nicht und können das Passwort nicht zurücksetzen. Nicht enthalten sind die App-Sperre und der Verlauf auf einer Box. Sehr große Datenbestände (über 256 MB) lehnt die App mit einem Hinweis ab.

Das Format ist offen, damit du auch ohne unsere App an deine Daten kommst: eine JSON-Datei, Schlüssel per PBKDF2-HMAC-SHA256 (600 000 Runden) aus dem Passwort, Inhalt mit AES-256-GCM verschlüsselt; entschlüsselt ein ZIP mit deinen Dateien im Klartext.

### Abgleich zwischen deinen Geräten (freiwillig, ab Plus)

Schaltest du „Geräte abgleichen“ ein, legt die App Anlagen, Projekte, Kundenakten, Fotos und Wächter verschlüsselt in deinem eigenen Speicher ab: unter iOS und macOS im privaten App-Ordner deiner iCloud, unter Android im versteckten App-Ordner deines Google Drive. Du brauchst dafür kein Konto bei uns, und an uns geht nichts. Verschlüsselt wird auf dem Gerät mit AES-256-GCM, der Schlüssel entsteht aus deinem Sync-Code und liegt im Schlüsselbund des Geräts. Apple bzw. Google sehen nur unlesbare Blöcke mit zufällig wirkenden Namen, deren Größe und Zeitpunkte und dass sie zu deinem Konto gehören. Unter Android holt die App dazu über die Google Play-Dienste eine Berechtigung, die nur diesen App-Ordner umfasst. Nicht im Abgleich: Verlauf, Keyrings, Einstellungen und alle Daten eines Betriebs. Es gelten zusätzlich die Datenschutzbestimmungen von [Apple](https://www.apple.com/de/legal/privacy/) bzw. [Google](https://policies.google.com/privacy). Beim Ausschalten kannst du den Stand in der Cloud mitlöschen; Dateien auf dem Gerät bleiben. Geht der Sync-Code verloren, kann niemand die Daten in der Cloud mehr lesen, auch wir nicht.

### Netzwerkzugriff

Die App greift ausschließlich auf das lokale Netzwerk zu, um per KNXnet/IP mit der von dir gewählten KNX-Schnittstelle bzw. dem IP-Router zu kommunizieren und Schnittstellen im Netzwerk zu finden. Dafür fragt iOS nach der Berechtigung „Lokales Netzwerk“. Die App selbst kommuniziert nicht mit dem Internet; Ausnahmen sind Käufe und die Abfrage deines Kaufstands (siehe „Käufe in der App“) und unter Android der QR-Scanner (siehe „Kamera und QR-Code“).

### Kamera, QR-Code und Fotos

Die Kamera läuft nur, wenn du sie auslöst: um einen QR-Code zu lesen (Busclear Box, Übergabe, Geräte-Etiketten) oder ein Foto des Verteilers aufzunehmen. Das Kamerabild eines Scans wird auf dem Gerät ausgewertet und weder gespeichert noch von der App übertragen. Fotos, die du aufnimmst oder auswählst, bleiben im Ordner der Anlage auf dem Gerät; Ort und Gerätedaten entfernt die App aus dem Bild. Sie stehen nicht im Diagnose- und nicht im Übergabepaket, in einen Servicebericht kommen sie nur, wenn du sie dort auswählst. In einer eigenen Sicherung sind sie enthalten.

Der QR-Code der Busclear Box enthält WLAN-Zugangsdaten und das Box-Passwort; damit tritt die App dem WLAN der Box bei und koppelt sich. Gespeichert wird danach nur der Gerätezugang und das WLAN der Box im Schlüsselbund des Systems, nicht das Box-Passwort.

Unter **Android** erkennt Googles ML Kit den QR-Code. ML Kit arbeitet auf dem Gerät, sendet aber technische Diagnosedaten an Google (z. B. Gerätemodell, Betriebssystem, App-Version, Leistungs- und Fehlerdaten sowie eine Kennung pro Installation), damit Google den Dienst betreiben und verbessern kann. Das Kamerabild ist nicht darunter. Das geschieht nur, wenn du den Scanner nutzt. Rechtsgrundlage ist unser berechtigtes Interesse an einem funktionierenden QR-Scanner (Art. 6 Abs. 1 lit. f DSGVO). Dabei kann eine Übermittlung in die USA stattfinden. Einzelheiten: [ML Kit – Datenoffenlegung](https://developers.google.com/ml-kit/android-data-disclosure) und die [Datenschutzerklärung von Google](https://policies.google.com/privacy). Unter iOS, iPadOS und macOS erkennt das System selbst (Apple Vision) den Code; dabei werden keine Daten übertragen.

### Busclear Box

Verbindest du die App mit einer Busclear Box, legt sie dein ETS-Projekt, eigene Datentypen und den Keyring auch auf der Box ab und liest deren Verlauf. Die Box ist dein eigenes Gerät im lokalen Netz. Die Daten verlassen es nur, wenn du selbst ein Ziel einrichtest (siehe „Das Home-Assistant-Add-on“); an uns gehen sie nicht. Sie liegen dort unverschlüsselt auf SD-Karte oder SSD, wer den Datenträger hat, kann sie lesen. Der Zugang ist durch das Box-Passwort und gekoppelte Geräte geschützt, das Passwort liegt nur als Hash auf der Box; im WLAN der Box läuft die Verbindung ohne TLS. Hat die Box Internet, stellt sie darüber ihre Uhr.

### Benachrichtigungen

Mitteilungen zu Alarmen und Wächtern erzeugt die App lokal auf dem Gerät; dein System fragt vorher um Erlaubnis, und du kannst sie in der App und im System abschalten. Es wird kein Push-Dienst eines Servers verwendet. Mitteilungen können auf dem Sperrbildschirm sichtbar sein, das regelst du in den Systemeinstellungen.

### Export und Teilen

Berichte (PDF), CSV- und ETS-Exporte werden nur erzeugt, wenn du das auslöst. Wohin sie gehen, bestimmst du über das Teilen-Menü deines Betriebssystems. Zuletzt erzeugte Exporte, auch Diagnosepakete, bleiben als Kopie in der App, damit du sie erneut teilen kannst; du kannst sie dort löschen. Eine Störungsmeldung an deinen Elektriker enthält neben der Busaufzeichnung die Namen der Adressen und Geräte, solange der Schalter dafür an ist; Bildschirmfotos an deinen Kommentaren nur, wenn du sie ausdrücklich einschließt. Sie geht nur an den Empfänger, den du wählst.

### Käufe in der App (Plus und Pro)

Plus und Pro kaufst du über den App Store bzw. Google Play; Zahlung und Zahlungsdaten liegen allein bei Apple bzw. Google. Damit die App erkennt, was du gekauft hast, nutzen wir den Dienst RevenueCat (RevenueCat, Inc., USA). Die App übermittelt dafür eine zufällige Kennung, die Kaufbelege des Stores sowie technische Angaben (z. B. App-Version, Betriebssystem, Sprache, IP-Adresse) an RevenueCat. Name, E-Mail-Adresse oder Daten deiner KNX-Anlage gehören nicht dazu. Das passiert, wenn du die Seite „Plus und Pro“ öffnest, etwas kaufst oder wiederherstellst, und bei jedem Start der App, um den Stand zu prüfen, **auch wenn du nie etwas gekauft hast.** Rechtsgrundlage ist bei einem Kauf die Erfüllung des Kaufvertrags (Art. 6 Abs. 1 lit. b DSGVO), sonst unser berechtigtes Interesse daran, gekaufte Stufen zuverlässig zu erkennen (Art. 6 Abs. 1 lit. f DSGVO). Dabei kann eine Übermittlung in die USA stattfinden. Einzelheiten: [Datenschutzerklärung von RevenueCat](https://www.revenuecat.com/privacy/). Unter Windows, unter Linux und im Add-on gibt es keine Käufe, dort findet das nicht statt.

### App Store und Google Play

Für den Download der App gelten die Datenschutzbestimmungen von Apple bzw. Google. Wenn du in den Systemeinstellungen deines Geräts zugestimmt hast, stellen Apple bzw. Google uns zusammengefasste, nicht personenbezogene Statistiken (z. B. Installationszahlen, Absturzberichte) bereit. Darauf haben wir keinen Einfluss, und wir können daraus keine Personen identifizieren.

## Das Home-Assistant-Add-on

Das Add-on läuft auf deinem eigenen Home-Assistant-Host. Alle Daten (Projekt, Secure-Schlüssel, Telegramme, Langzeitverlauf, Aufnahmen, Einstellungen) liegen im Datenordner des Add-ons auf diesem Host, sind unverschlüsselt und Teil deiner Home-Assistant-Sicherungen (schütze diese mit einem Sicherungsschlüssel) und werden beim Deinstallieren des Add-ons entfernt. Verschlüsselung, App-Sperre und Sicherung der Apps gibt es im Add-on nicht, dort übernimmt das dein Home Assistant. Das Add-on zeichnet den Bus dauerhaft auf, solange es läuft. Der Zugriff erfolgt über die Home-Assistant-Oberfläche (Ingress) und wird von Home Assistant authentifiziert. Die Integration „Busclear“ in deinem Home Assistant liest Zustände, Wächter und Hinweise mit einem eigenen Schlüssel; ohne Supervisor (Box, Docker) meldet sie sich als gekoppeltes Gerät an. Was sie liest, bleibt in deinem Home Assistant. Für Benachrichtigungen und das Mitlesen der KNX-Integration nutzt das Add-on die Schnittstelle von Home Assistant auf demselben Host. An uns sendet es nichts. Daten gehen nur an Ziele, die du selbst einrichtest, dort nach den Regeln dieser Anbieter: Mitteilungen an ntfy, einen Webhook oder Home Assistant, Messwerte an InfluxDB, Zustände und, wenn du „Jedes Telegramm an MQTT“ einschaltest, jedes Telegramm mit Adresse, Name und Wert an deinen MQTT-Broker; Prometheus holt sie auf deine Anfrage ab. Für die Box gilt dasselbe.

## Diese Website

### Hosting bei do.de

Diese Website liegt auf einem Webspace von do.de, einem Dienst der Greenmark IT GmbH, Leinstraße 3, 31061 Alfeld (Leine), Deutschland, mit Servern in der EU. Beim Aufruf der Seiten verarbeitet der Server technisch notwendige Daten, insbesondere deine IP-Adresse, Datum und Uhrzeit des Abrufs, die aufgerufene Adresse sowie Browser-Informationen, und speichert sie zur Sicherheit des Dienstes in Server-Logs. Rechtsgrundlage ist unser berechtigtes Interesse an einer sicheren und zuverlässigen Bereitstellung der Website (Art. 6 Abs. 1 lit. f DSGVO). Mit der Greenmark IT GmbH besteht ein Vertrag zur Auftragsverarbeitung nach Art. 28 DSGVO. Eine Übermittlung in Drittländer findet beim Hosting nicht statt. Die frühere Adresse knx-monitor.de liegt beim selben Anbieter und leitet auf diese Website weiter.

### Keine Cookies, kein Tracking, keine externen Inhalte

Diese Website setzt keine Cookies, verwendet keine Analyse- oder Tracking-Werkzeuge und bindet keine Inhalte von Drittanbietern ein. Die Schriften (Literata, Mona Sans, Monaspace und Material Symbols) werden von dieser Website selbst ausgeliefert, nicht von Google Fonts oder anderen Anbietern.

### Support über GitHub Issues

Support und Feedback laufen über GitHub Issues. Ein Issue ist öffentlich sichtbar und setzt ein Konto bei GitHub voraus; für die Verarbeitung dort gilt die [Datenschutzerklärung von GitHub](https://docs.github.com/de/site-policy/privacy-policies/github-general-privacy-statement). Wir nutzen deine Angaben im Issue nur, um deine Anfrage zu bearbeiten (Art. 6 Abs. 1 lit. b bzw. f DSGVO). Bitte veröffentliche dort keine vertraulichen Daten wie Passwörter oder dein ETS-Projekt. Nach einem Absturz kann die App ein Issue-Formular vorausfüllen; es enthält nur Version, Plattform, Zeit und Art des Absturzes, und du siehst es, bevor du es abschickst.

### Support per E-Mail und Diagnosepaket

Schreibst du uns eine E-Mail, etwa mit einem Diagnosepaket aus der App, verarbeiten wir deine E-Mail-Adresse, deine Nachricht und den Inhalt des Pakets nur, um deine Anfrage zu bearbeiten (Art. 6 Abs. 1 lit. b bzw. f DSGVO). Ein Diagnosepaket enthält die Busaufzeichnung um den Fehler, Gruppenadressen, Datenpunkttypen und Geräte aus deinem Projekt, deine Beschreibung und Kommentare, die letzten Meldungen der App und technische Eckdaten, darunter den Namen des Gateways. Dazu kommt, ob und wann du den Hinweis vor dem Schreiben auf den Bus ausgeblendet hast. Die Namen von Gruppenadressen und Geräten gehen mit, solange der Schalter dafür an ist. Screenshots gehen nur mit, wenn du das ausdrücklich einschaltest; **sie werden nicht gefiltert,** alles darauf Sichtbare kommt bei uns an. Nicht enthalten sind ETS-Projektdatei, Passwörter, Keyring und Schlüssel. Aus den Texten filtert die App, soweit erkennbar, IP-Adressen, Hostnamen, MAC- und Seriennummern, E-Mail-Adressen und bekannte Namen von Projekt, Installation und Kunde. **Das Paket kann trotzdem Personenbezug haben:** Telegrammwerte können zeigen, wann jemand zu Hause ist, und Namen, die du selbst eintippst oder die in Gruppenadressen stehen, erkennt der Filter nicht. Was genau drin ist, siehst du vor dem Senden in der App. Wir geben das Paket nicht weiter, veröffentlichen es nicht und löschen es, sobald deine Anfrage erledigt ist. E-Mails an support@busclear.de werden über do.de, einen Dienst der Greenmark IT GmbH, Leinstraße 3, 31061 Alfeld (Leine), Deutschland, empfangen und gespeichert.

## Instagram

Wir betreiben den Kanal [@busclear.app](https://www.instagram.com/busclear.app/) bei Instagram, einem Dienst der Meta Platforms Ireland Ltd. Unsere Websites binden Instagram nicht ein, sie verlinken nur dorthin; erst wenn du dem Link folgst, gelten die Bedingungen von Instagram. Meta verarbeitet dabei Daten der Besucher in eigener Regie und kann sie auch in die USA übermitteln. Für den Betrieb eines solchen Kanals kann eine gemeinsame Verantwortung mit dem Plattformbetreiber bestehen (EuGH, C-210/16, zu Facebook-Fanpages). Wir sehen, was Instagram uns zeigt: öffentliche Profile, Kommentare, Nachrichten und zusammengefasste Statistiken. Wir nutzen das, um mit dir zu sprechen und unser Angebot bekannt zu machen (Art. 6 Abs. 1 lit. f DSGVO). Einzelheiten: [Datenschutzrichtlinie von Instagram](https://privacycenter.instagram.com/policy/). Deine Rechte kannst du auch direkt bei Meta geltend machen.

## Deine Rechte

Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch (Art. 15–21 DSGVO) sowie das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren. Ohne Kauf übermittelt die App keine Daten an uns, dann liegen uns zu deiner Nutzung der App auch keine Daten vor. Für alle Anliegen genügt eine E-Mail an die Adresse im [Impressum](https://www.regetskcob.de/legal/). Zuständige Aufsichtsbehörde ist die Landesbeauftragte für Datenschutz und Informationsfreiheit Nordrhein-Westfalen ([www.ldi.nrw.de](https://www.ldi.nrw.de)).
