KNX Monitor für Linux
=====================

Busmonitor und Diagnose für KNX. Website: https://knx-monitor.de
(English below.)


Installieren
------------

1. Diesen Ordner („bundle“) im Dateimanager öffnen.

2. Hier ein Terminal öffnen:
   - KDE (Kubuntu, Dolphin): Taste F4, oder Rechtsklick in den Ordner
     → „Aktionen“ → „Terminal hier öffnen“.
   - GNOME (Ubuntu, Dateien): Rechtsklick in den Ordner
     → „Im Terminal öffnen“.

3. Eintippen und mit Enter bestätigen:

       ./install.sh

   Ein Passwort braucht es dafür nicht.

4. Fertig. „KNX Monitor“ steht jetzt im Startmenü, mit Icon, auch in der
   Leiste. Das Programm liegt unter ~/.local/opt/knx-monitor. Den
   heruntergeladenen Ordner kannst du löschen.

Ein Doppelklick auf install.sh öffnet je nach System nur einen Texteditor.
Dann bitte den Weg über das Terminal nehmen.


Aktualisieren
-------------

Neue Version herunterladen, entpacken und dort genauso ./install.sh
ausführen. Die alte Version wird ersetzt, sobald die neue komplett kopiert
ist. Läuft KNX Monitor gerade, danach einmal neu starten.


Deine Daten
-----------

Projekte, Aufnahmen, Verlauf und Einstellungen liegen getrennt vom
Programm in ~/.local/share/de.regetskcob.knxmonitor. Sie bleiben bei jedem
Update erhalten, und auch beim Entfernen.


Entfernen
---------

Im Terminal eintippen:

    ~/.local/opt/knx-monitor/install.sh --remove

Damit sind Programm und Startmenü-Eintrag weg. Wer auch die Daten löschen
will, löscht danach den Ordner ~/.local/share/de.regetskcob.knxmonitor.


Ohne Installation
-----------------

Die Datei knx_monitor in diesem Ordner startet KNX Monitor auch direkt.
Unter Wayland zeigt die Leiste dann aber nicht unser Icon.


Hilfe
-----

Fragen und Fehler: https://github.com/regetskcob/KNX-Monitor/issues
Lizenz: LICENSE.txt in diesem Ordner.


-----------------------------------------------------------------------------

KNX Monitor for Linux
=====================

Bus monitor and diagnostics for KNX. Website: https://knx-monitor.de/en/


Install
-------

1. Open this folder ("bundle") in your file manager.

2. Open a terminal here:
   - KDE (Kubuntu, Dolphin): press F4, or right-click in the folder
     → "Actions" → "Open Terminal Here".
   - GNOME (Ubuntu, Files): right-click in the folder
     → "Open in Terminal".

3. Type this and press Enter:

       ./install.sh

   No password is needed.

4. Done. "KNX Monitor" is now in the app menu, with its icon, also in the
   taskbar. The program lives in ~/.local/opt/knx-monitor. You can delete
   the downloaded folder.

Depending on your system, double-clicking install.sh may only open a text
editor. In that case use the terminal as above.


Update
------

Download the new version, unpack it and run ./install.sh there in the same
way. The old version is replaced once the new one is fully copied. If KNX
Monitor is running, restart it afterwards.


Your data
---------

Projects, recordings, history and settings are kept apart from the program
in ~/.local/share/de.regetskcob.knxmonitor. They stay with every update, and
also when you remove the program.


Remove
------

Type in a terminal:

    ~/.local/opt/knx-monitor/install.sh --remove

This removes the program and the app menu entry. To delete your data as
well, delete the folder ~/.local/share/de.regetskcob.knxmonitor afterwards.


Without installing
------------------

The file knx_monitor in this folder also starts KNX Monitor directly. Under
Wayland the taskbar then shows a generic icon instead of ours.


Help
----

Questions and bugs: https://github.com/regetskcob/KNX-Monitor/issues
License: LICENSE.txt in this folder.
