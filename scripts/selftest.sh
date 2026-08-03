#!/bin/bash
#
# selftest.sh — prüft die OCR-Toolchain, von der SpielplanOffline abhängt,
# die Saisonlogik aus saison.sh und die Auswertung der Fehlversuche am
# Eintrage-Formular aus loginwatch.sh.
#
# Fussball.de verschleiert Datum und Uhrzeit über einen eigenen Webfont: die
# Ziffern stehen als Codepoints aus dem Unicode-Private-Use-Bereich im HTML,
# erst der Font macht daraus lesbare Zahlen. SpielplanOffline lädt deshalb den
# Font, rendert die Codepoints mit ImageMagick zu einem Bild, liest sie per
# tesseract zurück und baut daraus eine Übersetzungstabelle.
#
# Scheitert einer dieser Schritte, bleibt die Verschleierung stehen: Vereine,
# Spielorte und Heim/Auswärts sind im Log korrekt, aber jedes Spiel steht auf
# "0.0.0" ohne Uhrzeit und wird mit "[FEHLER?]" markiert. Dieses Skript zeigt,
# welcher Schritt hakt.
#
# Aufruf:  ./selftest.sh          (nutzt einen Systemfont für den Test)
# Rückgabe: 0 = alles in Ordnung, 1 = mindestens ein Test fehlgeschlagen

set -uo pipefail

# Pfade der Installation, wie deploy.sh sie neben dieses Skript geschrieben hat
# (spo.env) — sonst prüfte der Selbsttest bei einem verschobenen Rollout den
# Standardpfad statt der tatsächlichen Installation. Umgebungsvariablen gehen vor.
SPO_ENV="${SPO_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spo.env}"
if [ -r "$SPO_ENV" ]; then
    . "$SPO_ENV"
fi

fehler=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mHINWEIS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFEHLER\033[0m %s\n' "$*"; fehler=1; }

echo "fussballcal — Selbsttest (OCR-Toolchain, Saisonlogik, Loginwatch)"
echo "------------------------------------------------------------------"

# ------------------------------------------------------------------
# 1. Programme vorhanden?
# ------------------------------------------------------------------
echo "[1] Benötigte Programme"
CONVERT=""
for prog in gawk wget perl iconv; do
    if command -v "$prog" >/dev/null 2>&1; then ok "$prog ($(command -v "$prog"))"
    else bad "$prog fehlt — 'sudo apt install $prog'"; fi
done

# ImageMagick 7 liefert nur noch 'magick', ältere Versionen 'convert'.
if command -v convert >/dev/null 2>&1; then
    CONVERT=$(command -v convert); ok "convert ($CONVERT)"
elif command -v magick >/dev/null 2>&1; then
    CONVERT=$(command -v magick)
    warn "nur 'magick' gefunden (ImageMagick 7), kein 'convert'."
    warn "In mysetup.sh CONVERT=$CONVERT setzen, sonst bricht SpielplanOffline ab."
else
    bad "ImageMagick fehlt — 'sudo apt install imagemagick'"
fi

if command -v tesseract >/dev/null 2>&1; then
    ok "tesseract ($(tesseract --version 2>&1 | head -1))"
    if tesseract --list-langs 2>/dev/null | grep -qx deu; then
        ok "Sprachpaket 'deu' vorhanden"
    else
        bad "Sprachpaket 'deu' fehlt — 'sudo apt install tesseract-ocr-deu'"
    fi
else
    bad "tesseract fehlt — 'sudo apt install tesseract-ocr tesseract-ocr-deu'"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------
# 2. Saisonlogik
# ------------------------------------------------------------------
# Braucht kein fussball.de und keine OCR: geprüft wird gegen synthetische
# ICS-Dateien, wie sie SpielplanOffline erzeugt. Der Punkt ist die
# Unterscheidung, die es vorher nicht gab — "leer, weil die Saison zu Ende ist"
# gegen "leer, weil die Toolchain kaputt ist".
echo
echo "[2] Saisonlogik (scripts/saison.sh)"
SAISON_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/saison.sh"
if [ ! -r "$SAISON_LIB" ]; then
    bad "saison.sh nicht gefunden neben $0 — update_all.sh bricht damit ab."
else
    . "$SAISON_LIB"

    pruef() { # pruef <beschreibung> <erwartet> <ist>
        if [ "$2" = "$3" ]; then ok "$1"
        else bad "$1 (erwartet '$2', ist '$3')"; fi
    }

    # Bausteine für eine ICS wie aus fussball2csv.awk. Der Zeitzonenblock im
    # Kopf enthält selbst eine DTSTART-Zeile — die darf nicht als Spiel zählen.
    mach_ics() {
        local f="$1" d; shift
        printf 'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VTIMEZONE\nTZID:Europe/Berlin\nDTSTART:19810329T020000\nEND:VTIMEZONE\n' >"$f"
        for d in "$@"; do
            printf '\nBEGIN:VEVENT\nUID:ID%s@SpielplanOffline\nDTSTART;TZID=Europe/Berlin:%sT153000\nDTEND;TZID=Europe/Berlin:%sT172000\nSUMMARY:A - B\nEND:VEVENT\n' "$d" "$d" "$d" >>"$f"
        done
        printf '\nEND:VCALENDAR\n' >>"$f"
    }

    URL2526='https://www.fussball.de/mannschaft/x/-/saison/2526/team-id/011MI#!/'

    # -- Fenster aus der URL
    if saison_aus_url "$URL2526"; then
        pruef "Saison aus der URL gelesen" "2526" "$SAISON"
        pruef "Fenster beginnt vor der Spielzeit" "2025-06-01" "$FENSTER_START"
        pruef "Fenster endet nach der Spielzeit" "2026-07-31" "$FENSTER_ENDE"
    else
        bad "saison_aus_url erkennt '.../saison/2526/...' nicht"
    fi
    if saison_aus_url 'https://www.fussball.de/verein/sv-beispiel/-/id/00ES1234'; then
        bad "Vereinslink liefert eine Saison, obwohl er nicht saisongebunden ist"
    else
        ok "Vereinslink liefert keine Saison (bleibt beim rollierenden Fenster)"
    fi

    # -- Statusermittlung
    status_fuer() { # status_fuer <heute> <spieldatum...>
        local heute="$1"; shift
        saison_aus_url "$URL2526" >/dev/null
        mach_ics "$TMP/saison.ics" "$@"
        ics_kennzahlen "$TMP/saison.ics" "$heute"
        saison_status "$heute"
        echo "$STATUS"
    }
    pruef "Spiel steht noch an"            "LAUFEND"                    "$(status_fuer 20260301 20260210 20260405)"
    pruef "Winterpause ist kein Saisonende" "LAUFEND"                   "$(status_fuer 20260105 20251220 20260210)"
    pruef "letztes Spiel innerhalb der Karenz" "LAUFEND"                "$(status_fuer 20260615 20260601)"
    pruef "letztes Spiel lange her"        "SAISONENDE_VERMUTLICH"      "$(status_fuer 20260711 20260601)"
    pruef "Saisonfenster abgelaufen"       "KEINE_SPIELE_MEHR_ERWARTET" "$(status_fuer 20270105 20260601)"
    pruef "leer am Saisonanfang"           "VORSAISON"                  "$(status_fuer 20250715)"
    pruef "leer mitten in der Saison"      "LEER_UNERWARTET"            "$(status_fuer 20260301)"

    # -- Hinweis-Termin
    saison_aus_url "$URL2526" >/dev/null
    mach_ics "$TMP/hinweis.ics" 20260510 20260601
    ics_kennzahlen "$TMP/hinweis.ics" 20260711
    ergaenze_saisonhinweis "$TMP/hinweis.ics" "tsv_test"
    pruef "Hinweis-Termin angehängt" "3" "$(grep -c '^BEGIN:VEVENT' "$TMP/hinweis.ics")"
    pruef "Kalender bleibt genau einmal geschlossen" "1" "$(grep -c '^END:VCALENDAR$' "$TMP/hinweis.ics")"
    pruef "END:VCALENDAR steht am Ende" "END:VCALENDAR" "$(tail -1 "$TMP/hinweis.ics")"
    pruef "Hinweis liegt nach dem letzten Spiel" "DTSTART;VALUE=DATE:20260602" \
          "$(grep '^DTSTART;VALUE=DATE:' "$TMP/hinweis.ics")"
    pruef "UID ist stabil (kein Duplikat in der App)" "UID:saisonende-tsv_test-2526@fussballcal" \
          "$(grep '^UID:saisonende' "$TMP/hinweis.ics")"
    if command -v iconv >/dev/null 2>&1; then
        if iconv -f UTF-8 -t UTF-8 "$TMP/hinweis.ics" >/dev/null 2>&1; then
            ok "Ausgabe ist gültiges UTF-8"
        else
            bad "Hinweis-Termin macht die Datei zu ungültigem UTF-8"
        fi
    fi

    unset -f pruef mach_ics status_fuer
fi

# ------------------------------------------------------------------
# 3. Auswertung der Fehlversuche am Formular
# ------------------------------------------------------------------
# Ebenfalls ohne fussball.de und ohne OCR: geprüft wird gegen synthetische
# nginx-Logzeilen. Der Punkt sind die beiden Verwechslungen, die den Bericht
# wertlos machen würden — die 401-Zeile jedes ganz normalen Seitenaufrufs als
# Angriff zu zählen, und Fehlversuche fremder vhosts derselben nginx-Instanz
# mitzuzählen.
echo
echo "[3] Fehlversuche am Formular (scripts/loginwatch.sh)"
LOGINWATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/loginwatch.sh"
if [ ! -x "$LOGINWATCH" ]; then
    warn "loginwatch.sh nicht gefunden neben $0 — Auswertung nicht geprüft."
else
    zeile() { # zeile <anzahl> <text-mit-client>
        local i
        for ((i = 0; i < $1; i++)); do
            printf '2026/03/01 12:00:%02d [error] 1#1: *%d %s\n' $((i % 60)) "$i" "$2"
        done
    }
    REQ='request: "GET /add_team.php HTTP/1.1", host: "x"'
    {
        zeile 30 "limiting requests, excess: 5.700 by zone \"fussballcal_login\", client: 203.0.113.7, server: _, $REQ"
        zeile 14 "user \"admin\": password mismatch, client: 203.0.113.8, server: _, $REQ"
        zeile  4 "user \"neu\" was not found in \"/etc/nginx/fussballcal.htpasswd\", client: 203.0.113.8, server: _, $REQ"
        # Muss ignoriert werden: die 401-Antwort, mit der jeder Login beginnt.
        zeile 99 "no user/password was provided for basic authentication, client: 198.51.100.1, server: _, $REQ"
        # Muss ignoriert werden: anderer vhost, andere Rate-Limit-Zone.
        zeile 99 'user "bob": password mismatch, client: 198.51.100.2, server: intern, request: "GET /webmail/ HTTP/1.1"'
        zeile 99 'limiting requests, excess: 1.000 by zone "andere", client: 198.51.100.3, server: _, request: "GET /x HTTP/1.1"'
    } >"$TMP/error.log"

    bericht="$(LOGINWATCH_LOG="$TMP/error.log" LOGINWATCH_STATE="$TMP/loginwatch.state" \
               "$LOGINWATCH" --dry-run 2>&1)" || true

    zeilen_fuer() { printf '%s\n' "$bericht" | awk -v ip="$1" '$1 == ip { print $2, $3 }'; }
    if [ "$(zeilen_fuer 203.0.113.7)" = "30 0" ]; then
        ok "Blocks aus der Rate-Limit-Zone werden gezählt (30)"
    else
        bad "Blocks falsch gezählt: '$(zeilen_fuer 203.0.113.7)' statt '30 0'"
    fi
    if [ "$(zeilen_fuer 203.0.113.8)" = "0 18" ]; then
        ok "Fehllogins werden gezählt (14 x falsches Passwort + 4 x unbekannter Benutzer)"
    else
        bad "Fehllogins falsch gezählt: '$(zeilen_fuer 203.0.113.8)' statt '0 18'"
    fi
    for ip in 198.51.100.1 198.51.100.2 198.51.100.3; do
        case "$ip" in
            *.1) was="die 401-Antwort jedes normalen Aufrufs" ;;
            *.2) was="Fehllogins eines fremden vhosts" ;;
            *)   was="eine fremde Rate-Limit-Zone" ;;
        esac
        if [ -z "$(zeilen_fuer "$ip")" ]; then
            ok "ignoriert: $was"
        else
            bad "$was wird mitgezählt ($ip) — der Bericht meldete damit Fehlalarme."
        fi
    done
    # Der Probelauf darf den Zustand nicht anfassen (sonst verschöbe ein
    # Selbsttest die Leseposition des Cron-Jobs).
    if [ -e "$TMP/loginwatch.state" ]; then
        bad "--dry-run hat eine Zustandsdatei geschrieben — das verschiebt den Cron-Job."
    else
        ok "--dry-run lässt den Zustand des Cron-Jobs unberührt"
    fi
    unset -f zeile zeilen_fuer
fi

# Die folgenden Abschnitte brauchen ImageMagick. Saisonlogik und Auswertung
# oben liefen schon durch, deshalb hier mit dem bisherigen Ergebnis aussteigen
# statt hart mit 1 — sonst verdeckte ein fehlendes ImageMagick, ob sie in
# Ordnung waren.
[ -n "$CONVERT" ] || { echo; echo "Ohne ImageMagick sind keine weiteren Tests möglich."; exit "$fehler"; }

PROBE="30.08.2026"
printf '%s\n%s\n%s\n' "$PROBE" "$PROBE" "$PROBE" > "$TMP/text.txt"

# Irgendeinen TrueType-Font zum Testen suchen (im Echtbetrieb kommt der Font
# von fussball.de).
FONT=$(fc-list -f '%{file}\n' 2>/dev/null | grep -i '\.ttf$' | sort | head -1)
[ -n "$FONT" ] || FONT=$(find /usr/share/fonts -name '*.ttf' 2>/dev/null | sort | head -1)

# ------------------------------------------------------------------
# 4. ImageMagick-Sicherheitsrichtlinie
# ------------------------------------------------------------------
echo
echo "[4] ImageMagick-Sicherheitsrichtlinie (policy.xml)"
if [ -z "$FONT" ]; then
    warn "kein TrueType-Font zum Testen gefunden — 'sudo apt install fonts-dejavu-core'"
else
    if "$CONVERT" -background white -fill black -font "$FONT" -pointsize 40 \
         label:@"$TMP/text.txt" "$TMP/at.png" >/dev/null 2>&1; then
        ok "'label:@datei' ist erlaubt"
    else
        warn "'label:@datei' ist durch policy.xml gesperrt (Standard unter Debian/Ubuntu:"
        warn "  <policy domain=\"path\" rights=\"none\" pattern=\"@*\"/>)."
        warn "Das ist in Ordnung — der gepatchte runscript.awk übergibt den Text direkt."
        warn "Achtung: Nach einem Update von vendor/SpielplanOffline muss der Patch"
        warn "erneut angewendet werden, sonst fehlen wieder alle Datums-/Zeitangaben."
    fi

    if "$CONVERT" -background white -fill black -font "$FONT" -pointsize 40 \
         -kerning 9 -interword-spacing 27 \
         label:"$(cat "$TMP/text.txt")" "$TMP/direkt.png" >/dev/null 2>&1 \
       && [ -s "$TMP/direkt.png" ]; then
        ok "Textrendering wie im gepatchten runscript.awk funktioniert"
    else
        bad "ImageMagick kann keinen Text rendern — ohne Bild gibt es keine OCR."
    fi
fi

# ------------------------------------------------------------------
# 5. OCR-Durchstich
# ------------------------------------------------------------------
echo
echo "[5] OCR-Durchstich (Text -> Bild -> Text)"
if [ -s "$TMP/direkt.png" ] && command -v tesseract >/dev/null 2>&1; then
    tesseract "$TMP/direkt.png" "$TMP/ocr" -l deu --psm 6 >/dev/null 2>&1
    if [ -s "$TMP/ocr.txt" ] && grep -q "$PROBE" "$TMP/ocr.txt"; then
        ok "'$PROBE' wurde korrekt zurückgelesen"
    else
        bad "OCR liefert nicht den erwarteten Text. Gelesen: $(tr '\n' ' ' < "$TMP/ocr.txt" 2>/dev/null)"
    fi
else
    bad "kein Testbild vorhanden — OCR-Durchstich übersprungen"
fi

# ------------------------------------------------------------------
# 6. Lokale Patches im vendorten Tool
# ------------------------------------------------------------------
echo
echo "[6] Lokale Patches in SpielplanOffline"
TOOL_DIR="${SPO_TOOL_DIR:-/srv/spielplanoffline/SpielplanOffline}"
if [ -d "$TOOL_DIR" ]; then
    if grep -q 'label:\\"\$(cat ' "$TOOL_DIR/runscript.awk" 2>/dev/null; then
        ok "runscript.awk: Patch für die ImageMagick-Richtlinie ist aktiv"
    else
        bad "runscript.awk in $TOOL_DIR ist ungepatcht (nutzt noch 'label:@datei')."
    fi
    if grep -q 'halbiere die Seitenlaenge' "$TOOL_DIR/runscript.awk" 2>/dev/null; then
        ok "runscript.awk: Patch für die selbstregelnde Seitenlänge ist aktiv"
    else
        bad "runscript.awk in $TOOL_DIR hat keine selbstregelnde Seitenlänge — bei großen"
        bad "Spielplänen scheitert ImageMagick mit 'width or height exceeds limit'."
    fi
    if grep -q ">:utf8" "$TOOL_DIR/iconv.perl" 2>/dev/null; then
        ok "iconv.perl: Patch für UTF-8-Ausgabe ist aktiv"
    else
        bad "iconv.perl in $TOOL_DIR ist ungepatcht — Umlaute landen als Latin-1 in der .ics."
    fi
else
    warn "$TOOL_DIR nicht gefunden (kein installiertes Tool geprüft)."
    warn "Pfad ggf. per SPO_TOOL_DIR setzen."
fi

echo "------------------------------------------------------------------"
if [ "$fehler" -eq 0 ]; then
    echo "Ergebnis: Toolchain in Ordnung."
else
    echo "Ergebnis: Es gibt Probleme (siehe FEHLER oben)."
fi
exit "$fehler"
