#!/bin/bash
#
# update_all.sh
# Liest teams.txt (slug;url) und erzeugt pro Zeile eine ICS-Datei unter
# $OUTDIR/<slug>.ics via SpielplanOffline.
#
# Aufrufkonvention von SpielplanOffline (aus dem Tar-Archiv verifiziert,
# V2.9 / 2021):
#   ./SpielplanOffline.sh -var <paramfile>
# Der <paramfile> wird von SpielplanOffline.sh gesourct und setzt die
# Parameter als Shell-Variablen (NICHT als --flags). Relevante Variablen:
#   url, csvfile, outdir, STYLE, startdate, enddate, backgroundprocessing
# Ausgabedatei entsteht als  <outdir>/<csvfile>.<ext>  (ext=ics bei STYLE=ICS).
#
# Voraussetzungen auf dem Server: gawk, wget, tesseract (+ tesseract-ocr-deu),
# ImageMagick (convert), perl. Siehe README.

set -euo pipefail

# Verzeichnis mit SpielplanOffline.sh (im Tar liegt alles im Unterordner
# SpielplanOffline/). Hier liegt auch mysetup.sh (Linux-Overrides).
TOOL_DIR="${SPO_TOOL_DIR:-/opt/spielplanoffline/SpielplanOffline}"
CONFIG="${SPO_CONFIG:-/opt/spielplanoffline/teams.txt}"
OUTDIR="${SPO_OUTDIR:-/var/www/fussballcal/ics}"
LOCKFILE="${SPO_LOCK:-/tmp/fussballcal_update.lock}"
LOG="${SPO_LOG:-/var/log/spielplanoffline.log}"

# Arbeits-/Cache-Verzeichnis. SpielplanOffline legt unter $HOME/SpielplanOffline
# seine tmp/Fonts/Output-Ordner an (ROOTDIR=$HOME). Wir setzen HOME bewusst auf
# einen definierten, beschreibbaren Pfad, damit das unabhängig vom Cron-User ist.
export HOME="${SPO_HOME:-/opt/spielplanoffline/work}"

# Zeitfenster, in dem Spiele in den Kalender aufgenommen werden.
STARTDATE="${SPO_START:-$(date -d '-2 months' +%F)}"
ENDDATE="${SPO_END:-$(date -d '+12 months' +%F)}"

mkdir -p "$OUTDIR" "$HOME"

# Verhindert überlappende Läufe, falls ein Update länger dauert als der Cron-Takt
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date -Is) Update läuft bereits, breche ab." >>"$LOG"; exit 1; }

log() { echo "$(date -Is) $*" >>"$LOG"; }

if [ ! -x "$TOOL_DIR/SpielplanOffline.sh" ]; then
    log "SpielplanOffline.sh nicht gefunden/ausführbar unter $TOOL_DIR, breche ab."
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    log "Keine Konfigdatei $CONFIG gefunden, breche ab."
    exit 1
fi

log "Update-Lauf gestartet (Zeitfenster $STARTDATE .. $ENDDATE)."

while IFS=';' read -r slug url; do
    # Leerzeilen und Kommentare überspringen
    [[ -z "${slug:-}" || "$slug" =~ ^# ]] && continue

    # Whitespace um die Felder entfernen
    slug="${slug//[[:space:]]/}"
    url="$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Slug validieren (nur sichere Zeichen, wird als Dateiname verwendet)
    if [[ ! "$slug" =~ ^[a-z0-9_-]+$ ]]; then
        log "Ungültiger Slug '$slug', übersprungen."
        continue
    fi

    # URL validieren (nur fussball.de erlaubt)
    if [[ ! "$url" =~ ^https?://www\.fussball\.de/ ]]; then
        log "Ungültige URL für '$slug', übersprungen: $url"
        continue
    fi

    log "Verarbeite $slug ($url)"

    TMP_OUT="$(mktemp -d)"
    TMP_IN="$(mktemp)"

    # Parameterdatei für den -var-Modus erzeugen. Wird von SpielplanOffline.sh
    # gesourct; deshalb als Shell-Zuweisungen. csvfile=slug -> <slug>.ics.
    # backgroundprocessing=1 unterdrückt das Mac-"open" am Ende.
    cat >"$TMP_IN" <<EOF
url="$url"
csvfile="$slug"
outdir="$TMP_OUT"
STYLE=ICS
startdate=$STARTDATE
enddate=$ENDDATE
prefix=""
NurHeimspiele=0
NurAuswaertsspiele=0
ignoriereAbgesagt=0
backgroundprocessing=1
EOF

    if ! ( cd "$TOOL_DIR" && ./SpielplanOffline.sh -var "$TMP_IN" ) >>"$LOG" 2>&1; then
        log "WARNUNG: SpielplanOffline meldete Fehlercode für $slug (prüfe Log)."
        # Nicht sofort abbrechen – ggf. wurde die Datei trotzdem erzeugt.
    fi

    if [ -s "$TMP_OUT/$slug.ics" ]; then
        # Atomarer Ersatz, damit nginx nie eine halb geschriebene Datei ausliefert
        mv "$TMP_OUT/$slug.ics" "$OUTDIR/$slug.ics.new"
        mv "$OUTDIR/$slug.ics.new" "$OUTDIR/$slug.ics"
        log "OK: $slug.ics aktualisiert"
    else
        log "FEHLER: keine (nicht-leere) Ausgabedatei für $slug erzeugt"
    fi

    rm -rf "$TMP_OUT" "$TMP_IN"

done < "$CONFIG"

log "Update-Lauf abgeschlossen."
