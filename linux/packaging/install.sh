#!/bin/bash
# KNX Monitor installieren (nur für den eigenen Benutzer, ohne sudo).
#
#   ./install.sh            nach ~/.local/opt/knx-monitor kopieren und ins
#                           App-Menü eintragen; mit einer neuen Version: Update
#   ./install.sh --remove   Programm und Eintrag wieder entfernen
#
# Danach kann der entpackte Download weg. Projekte, Verlauf und Einstellungen
# liegen getrennt im Benutzerprofil und bleiben bei Update und Entfernen.
# Anderer Ort: KNX_MONITOR_HOME=/pfad ./install.sh
#
# Unter Wayland holen GNOME und KDE Plasma das Icon für Leiste und Dock nur
# aus einem Eintrag, dessen Name zur App-ID passt; ohne ihn zeigen sie ein
# Ersatzsymbol (GNOME ein Zahnrad, Plasma ein „W“).
set -euo pipefail

id=de.regetskcob.knxmonitor
here=$(cd "$(dirname "$0")" && pwd)
target=${KNX_MONITOR_HOME:-$HOME/.local/opt/knx-monitor}
data=${XDG_DATA_HOME:-$HOME/.local/share}
desktop=$data/applications/$id.desktop
icon=$data/icons/hicolor/256x256/apps/$id.png

refresh() {
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$data/applications" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$data/icons/hicolor" || true
  # KDE Plasma liest das App-Menü aus seinem eigenen Cache.
  for k in kbuildsycoca6 kbuildsycoca5; do
    if command -v "$k" >/dev/null; then "$k" >/dev/null 2>&1 || true; break; fi
  done
}

if [ "${1:-}" = --remove ]; then
  rm -f "$desktop" "$icon"
  # Nur einen Ordner löschen, der wirklich KNX Monitor ist.
  if [ -x "$target/knx_monitor" ] && [ -f "$target/install.sh" ]; then
    rm -rf "$target"
  fi
  refresh
  echo "KNX Monitor ist entfernt. Deine Projekte und der Verlauf bleiben im Benutzerprofil."
  exit 0
fi

[ -x "$here/knx_monitor" ] || { echo "knx_monitor nicht gefunden: install.sh im entpackten Ordner ausführen." >&2; exit 1; }

# Kopieren, außer das Skript läuft schon am Zielort (Eintrag erneuern).
if [ "$here" != "$(cd "$target" 2>/dev/null && pwd || echo "$target")" ]; then
  install -d "$(dirname "$target")"
  rm -rf "$target.new"
  cp -R "$here" "$target.new"
  # Erst ganz kopiert, dann austauschen: Bricht das Kopieren ab, bleibt die
  # alte Version heil.
  rm -rf "$target.old"
  [ -d "$target" ] && mv "$target" "$target.old"
  mv "$target.new" "$target"
  rm -rf "$target.old"
  updated=1
fi

install -d "$(dirname "$desktop")" "$(dirname "$icon")"
install -m 0644 "$target/data/app_icon.png" "$icon"
# Exec mit Anführungszeichen, falls der Pfad Leerzeichen enthält.
cat >"$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=KNX Monitor
GenericName=KNX-Busmonitor
GenericName[en]=KNX bus monitor
Comment=Busmonitor und Diagnose für KNX
Comment[en]=Bus monitor and diagnostics for KNX
Exec="$target/knx_monitor"
Icon=$id
Terminal=false
Categories=Utility;Network;
Keywords=KNX;ETS;Busmonitor;Gebäudeautomation;
StartupWMClass=$id
EOF
refresh
echo "KNX Monitor ist installiert in $target und steht im App-Menü."
if [ -n "${updated:-}" ]; then
  echo "Den entpackten Ordner $here kannst du jetzt löschen. Läuft die App gerade, einmal neu starten."
fi
