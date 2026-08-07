#!/bin/bash
#
# update_all.sh
# Liest teams.txt (slug;url) und erzeugt pro Zeile eine ICS-Datei unter
# $OUTDIR/<slug>.ics via SpielplanOffline. Daneben entsteht $OUTDIR/<slug>.state
# mit dem Saisonstatus, den die Webseiten anzeigen (siehe saison.sh).
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

# Pfade der Installation, wie deploy.sh sie neben dieses Skript geschrieben hat
# (spo.env). Damit stimmen die Vorgaben unten auch bei einem verschobenen
# Rollout. Bereits gesetzte Umgebungsvariablen behalten Vorrang.
SPO_ENV="${SPO_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spo.env}"
if [ -r "$SPO_ENV" ]; then
    . "$SPO_ENV"
fi

# Verzeichnis mit SpielplanOffline.sh (im Tar liegt alles im Unterordner
# SpielplanOffline/). Hier liegt auch mysetup.sh (Linux-Overrides).
TOOL_DIR="${SPO_TOOL_DIR:-/srv/spielplanoffline/SpielplanOffline}"
CONFIG="${SPO_CONFIG:-/srv/spielplanoffline/teams.txt}"
OUTDIR="${SPO_OUTDIR:-/var/www/fussballcal/ics}"
LOCKFILE="${SPO_LOCK:-/tmp/fussballcal_update_$(id -u).lock}"
LOG="${SPO_LOG:-/var/log/spielplanoffline.log}"

# Arbeits-/Cache-Verzeichnis. SpielplanOffline legt unter $HOME/SpielplanOffline
# seine tmp/Fonts/Output-Ordner an (ROOTDIR=$HOME). Wir setzen HOME bewusst auf
# einen definierten, beschreibbaren Pfad, damit das unabhängig vom Cron-User ist.
export HOME="${SPO_HOME:-/srv/spielplanoffline/work}"

# Zeitfenster, in dem Spiele in den Kalender aufgenommen werden.
#
# Vorgabe ist das Saisonfenster aus der URL der jeweiligen Zeile (siehe
# saison_aus_url()). Nur wo sich keine Saison ablesen lässt — Vereinslinks,
# die gar nicht saisongebunden sind — bleibt es beim alten rollierenden
# Fenster. SPO_START/SPO_END setzen beides außer Kraft und gelten dann für
# alle Zeilen; das ist der Notausgang, wenn ein Verband die Spielzeit
# streckt (siehe README, "Saisonwechsel").
ROLL_STARTDATE="$(date -d '-2 months' +%F)"
ROLL_ENDDATE="$(date -d '+12 months' +%F)"

# Saisonlogik: Fenster aus der URL, Statusermittlung, Hinweis-Termin. Liegt
# neben diesem Skript (deploy.sh installiert beide zusammen) und wird auch von
# selftest.sh eingebunden, damit die Klassifikation testbar bleibt.
SAISON_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/saison.sh"
if [ ! -r "$SAISON_LIB" ]; then
    echo "$(date -Is) saison.sh nicht gefunden neben $0, breche ab." >&2
    exit 1
fi
. "$SAISON_LIB"

HEUTE="$(date +%Y%m%d)"

mkdir -p "$OUTDIR" "$HOME"

# Zentrales Temp-Verzeichnis für diesen Lauf. Der EXIT-Trap räumt es zuverlässig
# auf – auch bei set -e-Abbruch oder SIGINT/SIGTERM.
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

# Verhindert überlappende Läufe, falls ein Update länger dauert als der Cron-Takt
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date -Is) Update läuft bereits, breche ab." >>"$LOG"; exit 1; }

log() { echo "$(date -Is) $*" >>"$LOG"; }

# Erkennt eine unbrauchbare Ausgabe – im Unterschied zu einer bloß leeren.
#
# Hintergrund: SpielplanOffline liefert auch dann eine (syntaktisch gültige)
# ICS-Datei zurück, wenn die Datums-/Zeit-Entschlüsselung fehlgeschlagen ist –
# die Termine stehen dann auf dem Jahr 0000 und tragen im SUMMARY die Marke
# "[FEHLER?]". Der Exit-Code hilft nicht weiter: SpielplanOffline.sh reicht den
# Fehlercode des awk-Laufs nicht durch. Ohne diese Prüfung überschreibt der
# Cron-Lauf einen funktionierenden Kalender mit Müll.
#
# "Keine Termine" ist hier bewusst KEIN Fehler mehr – das entscheidet
# saison_status(), weil eine leere Ausgabe am Saisonende der Normalfall ist.
ics_kaputt() {
    local f="$1" name="$2"

    # Jahr 0000/00xx im DTSTART => Datum wurde nicht erkannt.
    if grep -qE '^DTSTART[^:]*:0{4}' "$f"; then
        log "PRÜFUNG $name: Termine ohne erkanntes Datum (DTSTART Jahr 0000)." \
            "Meist scheitert die OCR-Entschlüsselung – 'scripts/selftest.sh' prüft die Toolchain."
        return 0
    fi

    # Marker, den fussball2csv.awk bei nicht erkanntem Datum//Zeit setzt.
    if grep -q '\[FEHLER?\]' "$f"; then
        log "PRÜFUNG $name: SpielplanOffline hat Termine als [FEHLER?] markiert."
        return 0
    fi

    # RFC 5545 verlangt UTF-8; kaputte Umlaute fallen sonst erst im Kalender auf.
    if command -v iconv >/dev/null 2>&1 && ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
        log "PRÜFUNG $name: Datei ist nicht UTF-8-kodiert."
        return 0
    fi

    return 1
}

# Schreibt die Statusdatei neben die ICS. Bewusst flach und menschenlesbar –
# passend zum Rest des Projekts, das ohne Datenbank auskommt.
schreibe_status() {
    local slug="$1" ziel="$OUTDIR/$slug.state"

    cat >"$ziel.new" <<EOF
# Von update_all.sh erzeugt – nicht von Hand pflegen.
status=$STATUS
saison=${SAISON:-}
saison_nominalende=${SAISON_NOMINALENDE:-}
fenster_start=${FENSTER_START:-}
fenster_ende=${FENSTER_ENDE:-}
letztes_spiel=${LETZTES_SPIEL:-}
spiele_zukunft=${SPIELE_ZUKUNFT:-0}
termine=${NEVENTS:-0}
geprueft=$(date -Is)
EOF
    mv "$ziel.new" "$ziel"
}

if [ ! -x "$TOOL_DIR/SpielplanOffline.sh" ]; then
    log "SpielplanOffline.sh nicht gefunden/ausführbar unter $TOOL_DIR, breche ab."
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    log "Keine Konfigdatei $CONFIG gefunden, breche ab."
    exit 1
fi

if [ -n "${SPO_START:-}${SPO_END:-}" ]; then
    log "Update-Lauf gestartet (Zeitfenster fest vorgegeben:" \
        "${SPO_START:-$ROLL_STARTDATE} .. ${SPO_END:-$ROLL_ENDDATE})."
else
    log "Update-Lauf gestartet (Zeitfenster je Zeile aus der Saison der URL," \
        "sonst rollierend $ROLL_STARTDATE .. $ROLL_ENDDATE)."
fi

# `|| [[ -n ... ]]` sorgt dafür, dass auch die letzte Zeile ohne abschließenden
# Zeilenumbruch verarbeitet wird (read liefert dann Exit-Code != 0).
while IFS=';' read -r slug url || [[ -n "${slug:-}" ]]; do
    # Whitespace zuerst entfernen, damit auch eingerückte Kommentare/Leerzeilen
    # (z.B. "  # ...") zuverlässig und ohne Log-Spam übersprungen werden.
    slug="${slug//[[:space:]]/}"
    url="$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Leerzeilen und Kommentare überspringen
    [[ -z "$slug" || "$slug" =~ ^# ]] && continue

    # Slug validieren (nur sichere Zeichen, wird als Dateiname verwendet)
    if [[ ! "$slug" =~ ^[a-z0-9_-]+$ ]]; then
        log "Ungültiger Slug '$slug', übersprungen."
        continue
    fi

    # URL validieren: nur fussball.de und nur ein für URLs plausibler Zeichensatz.
    # Das schließt Shell-Metazeichen (" ` $ ; ( ) | Whitespace ...) aus – wichtig,
    # weil die Parameterdatei unten von SpielplanOffline.sh gesourct wird.
    if [[ ! "$url" =~ ^https?://www\.fussball\.de/[A-Za-z0-9/._~:%?=\&!#-]+$ ]]; then
        log "Ungültige URL für '$slug', übersprungen: $url"
        continue
    fi

    # Saisonfenster dieser Zeile bestimmen. Vereinslinks (.../verein/.../id/...)
    # nennen keine Saison und sind auch nicht saisongebunden – die erzeugte
    # Druck-URL enthält weder Saison noch team-id. Für die bleibt es beim
    # rollierenden Fenster, und sie bekommen keinen Saisonstatus.
    if [ -n "${SPO_START:-}${SPO_END:-}" ]; then
        SAISON=""; SAISON_NOMINALENDE=""
        FENSTER_START="${SPO_START:-$ROLL_STARTDATE}"
        FENSTER_ENDE="${SPO_END:-$ROLL_ENDDATE}"
        log "Verarbeite $slug ($url) – Fenster $FENSTER_START .. $FENSTER_ENDE (vorgegeben)"
    elif saison_aus_url "$url"; then
        log "Verarbeite $slug ($url) – Saison ${SAISON:0:2}/${SAISON:2:2}," \
            "Fenster $FENSTER_START .. $FENSTER_ENDE"
    else
        SAISON=""; SAISON_NOMINALENDE=""
        FENSTER_START="$ROLL_STARTDATE"
        FENSTER_ENDE="$ROLL_ENDDATE"
        log "Verarbeite $slug ($url) – keine Saison in der URL," \
            "Fenster rollierend $FENSTER_START .. $FENSTER_ENDE"
    fi

    TMP_OUT="$TMP_BASE/out_$slug"
    TMP_IN="$TMP_BASE/in_$slug"
    mkdir -p "$TMP_OUT"

    # Parameterdatei für den -var-Modus erzeugen. Wird von SpielplanOffline.sh
    # gesourct; deshalb als Shell-Zuweisungen. csvfile=slug -> <slug>.ics.
    # backgroundprocessing=1 unterdrückt das Mac-"open" am Ende.
    #
    # SICHERHEIT: Die (extern kontrollierte) URL wird NICHT literal in die Datei
    # geschrieben, sondern über die exportierte Variable FUSSBALL_URL referenziert.
    # Beim Sourcen expandiert bash "$FUSSBALL_URL" als einzelnes Wort, ohne den
    # Inhalt erneut als Code auszuwerten -> keine Command Injection möglich.
    export FUSSBALL_URL="$url"
    cat >"$TMP_IN" <<EOF
url="\$FUSSBALL_URL"
csvfile="$slug"
outdir="$TMP_OUT"
STYLE=ICS
startdate=$FENSTER_START
enddate=$FENSTER_ENDE
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

    if [ ! -s "$TMP_OUT/$slug.ics" ]; then
        log "FEHLER: keine (nicht-leere) Ausgabedatei für $slug erzeugt"
    elif ics_kaputt "$TMP_OUT/$slug.ics" "$slug"; then
        log "FEHLER: $slug.ics verworfen – bestehende Datei bleibt unverändert."
    else
        entferne_laufende_nummer "$TMP_OUT/$slug.ics"
        ics_kennzahlen "$TMP_OUT/$slug.ics" "$HEUTE"
        saison_status "$HEUTE"

        if fenster_zu_eng; then
            log "WARNUNG $slug: letztes Spiel ($LETZTES_SPIEL) liegt dicht am Fensterende" \
                "($FENSTER_ENDE) – möglicherweise abgeschnitten. SPO_SAISON_NACHLAUF erhöhen."
        fi

        # Eine terminlose Ausgabe wird nie veröffentlicht, egal aus welchem
        # Grund sie leer ist: die bestehende Datei ist das Archiv der Saison,
        # und die gegen einen leeren Kalender zu tauschen nimmt den Abonnenten
        # auch noch den Spielplan, den sie schon hatten.
        if [ "$NEVENTS" -eq 0 ]; then
            case "$STATUS" in
                VORSAISON)
                    log "HINWEIS $slug: noch keine Spiele angesetzt (Saisonanfang)." \
                        "Kein Fehler, bestehende Datei bleibt unverändert."
                    ;;
                KEINE_SPIELE_MEHR_ERWARTET)
                    log "HINWEIS $slug: fussball.de liefert für die Saison" \
                        "${SAISON:-?} keine Spiele mehr, das Saisonfenster ist abgelaufen." \
                        "Kein Fehler – die bestehende Datei bleibt als Archiv stehen."
                    ;;
                *)
                    # Wie bisher: lieber ein veralteter Kalender als ein leerer.
                    log "PRÜFUNG $slug: keine Termine in der Ausgabe, und das Saisonfenster" \
                        "($FENSTER_START .. $FENSTER_ENDE) spricht nicht dafür."
                    log "FEHLER: $slug.ics verworfen – bestehende Datei bleibt unverändert."
                    ;;
            esac
            schreibe_status "$slug"
            rm -rf "$TMP_OUT" "$TMP_IN"
            continue
        fi

        case "$STATUS" in
            LEER_UNERWARTET)
                # Kann mit Terminen nicht auftreten, aber lieber verwerfen als
                # stillschweigend veröffentlichen, wenn sich das je ändert.
                log "FEHLER: $slug.ics verworfen – bestehende Datei bleibt unverändert."
                ;;
            *)
                if [ "$STATUS" != "LAUFEND" ]; then
                    ergaenze_saisonhinweis "$TMP_OUT/$slug.ics" "$slug"
                fi

                # Atomarer Ersatz, damit nginx nie eine halb geschriebene Datei ausliefert
                mv "$TMP_OUT/$slug.ics" "$OUTDIR/$slug.ics.new"
                mv "$OUTDIR/$slug.ics.new" "$OUTDIR/$slug.ics"

                case "$STATUS" in
                    LAUFEND)
                        log "OK: $slug.ics aktualisiert ($NEVENTS Termine," \
                            "$SPIELE_ZUKUNFT davon noch offen)."
                        ;;
                    SAISONENDE_VERMUTLICH)
                        log "OK: $slug.ics aktualisiert ($NEVENTS Termine)." \
                            "Kein Spiel mehr in der Zukunft, letztes am $LETZTES_SPIEL –" \
                            "Saison vermutlich beendet, Hinweis-Termin angehängt." \
                            "Nachhol- oder Pokalspiele können das zurückdrehen."
                        ;;
                    KEINE_SPIELE_MEHR_ERWARTET)
                        log "OK: $slug.ics aktualisiert ($NEVENTS Termine)." \
                            "Saisonfenster (bis $FENSTER_ENDE) ist abgelaufen –" \
                            "es sind keine weiteren Spiele zu erwarten. Neuen Link für die" \
                            "kommende Saison eintragen (README, 'Saisonwechsel')."
                        ;;
                esac
                ;;
        esac

        schreibe_status "$slug"
    fi

    rm -rf "$TMP_OUT" "$TMP_IN"

done < "$CONFIG"

log "Update-Lauf abgeschlossen."
