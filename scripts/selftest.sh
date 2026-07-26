#!/bin/bash
#
# selftest.sh — prüft die OCR-Toolchain, von der SpielplanOffline abhängt.
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

fehler=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mHINWEIS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFEHLER\033[0m %s\n' "$*"; fehler=1; }

echo "SpielplanOffline — Selbsttest der OCR-Toolchain"
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

[ -n "$CONVERT" ] || { echo; echo "Ohne ImageMagick sind keine weiteren Tests möglich."; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PROBE="30.08.2026"
printf '%s\n%s\n%s\n' "$PROBE" "$PROBE" "$PROBE" > "$TMP/text.txt"

# Irgendeinen TrueType-Font zum Testen suchen (im Echtbetrieb kommt der Font
# von fussball.de).
FONT=$(fc-list -f '%{file}\n' 2>/dev/null | grep -i '\.ttf$' | sort | head -1)
[ -n "$FONT" ] || FONT=$(find /usr/share/fonts -name '*.ttf' 2>/dev/null | sort | head -1)

# ------------------------------------------------------------------
# 2. ImageMagick-Sicherheitsrichtlinie
# ------------------------------------------------------------------
echo
echo "[2] ImageMagick-Sicherheitsrichtlinie (policy.xml)"
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
# 3. OCR-Durchstich
# ------------------------------------------------------------------
echo
echo "[3] OCR-Durchstich (Text -> Bild -> Text)"
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
# 4. Lokale Patches im vendorten Tool
# ------------------------------------------------------------------
echo
echo "[4] Lokale Patches in SpielplanOffline"
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
