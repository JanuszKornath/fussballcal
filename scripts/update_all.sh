#!/bin/bash
#
# update_all.sh
# Liest teams.txt (slug;url) und erzeugt pro Zeile eine ICS-Datei
# unter $OUTDIR/<slug>.ics via SpielplanOffline.
#
# WICHTIG: Der genaue Aufruf von SpielplanOffline.sh (Parameter, Output-Pfad,
# Rolle von myinput.sh/setup.sh) ist hier als Platzhalter markiert (TODO) und
# muss anhand der tatsächlichen Skripte im entpackten Tar-Archiv geprüft/
# angepasst werden.

set -euo pipefail

TOOL_DIR="/opt/spielplanoffline"
CONFIG="$TOOL_DIR/teams.txt"
OUTDIR="/var/www/fussballcal/ics"
LOCKFILE="/tmp/fussballcal_update.lock"
LOG="/var/log/spielplanoffline.log"

mkdir -p "$OUTDIR"

# Verhindert überlappende Läufe, falls ein Update länger dauert als der Cron-Takt
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date -Is) Update läuft bereits, breche ab." >>"$LOG"; exit 1; }

log() { echo "$(date -Is) $*" >>"$LOG"; }

if [ ! -f "$CONFIG" ]; then
    log "Keine Konfigdatei $CONFIG gefunden, breche ab."
    exit 1
fi

while IFS=';' read -r slug url; do
    # Leerzeilen und Kommentare überspringen
    [[ -z "$slug" || "$slug" =~ ^# ]] && continue

    # Slug validieren (nur sichere Zeichen, wird als Dateiname verwendet)
    if [[ ! "$slug" =~ ^[a-z0-9_-]+$ ]]; then
        log "Ungültiger Slug '$slug', übersprungen."
        continue
    fi

    # URL validieren (nur fussball.de erlaubt)
    if [[ ! "$url" =~ ^https://www\.fussball\.de/ ]]; then
        log "Ungültige URL für '$slug', übersprungen: $url"
        continue
    fi

    log "Verarbeite $slug ($url)"

    cd "$TOOL_DIR"

    TMP_OUT=$(mktemp -d)

    # TODO: An tatsächliche Aufrufkonvention anpassen. Platzhalter-Annahme:
    # ./SpielplanOffline.sh erzeugt im aktuellen Verzeichnis eine Datei
    # namens spielplan.ics, gesteuert über eine generierte input-Datei
    # oder Kommandozeilenparameter mit URL + style=ICS.
    if ! ./SpielplanOffline.sh "$url" --style=ICS --output="$TMP_OUT/spielplan.ics" >>"$LOG" 2>&1; then
        log "FEHLER beim Verarbeiten von $slug"
        rm -rf "$TMP_OUT"
        continue
    fi

    if [ -f "$TMP_OUT/spielplan.ics" ]; then
        # Atomarer Ersatz, damit nginx nie eine halb geschriebene Datei ausliefert
        mv "$TMP_OUT/spielplan.ics" "$OUTDIR/$slug.ics.new"
        mv "$OUTDIR/$slug.ics.new" "$OUTDIR/$slug.ics"
        log "OK: $slug.ics aktualisiert"
    else
        log "FEHLER: keine Ausgabedatei für $slug erzeugt"
    fi

    rm -rf "$TMP_OUT"

done < "$CONFIG"

log "Update-Lauf abgeschlossen."
