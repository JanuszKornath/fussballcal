# mysetup.sh — Linux/Debian-Overrides für SpielplanOffline.
#
# SpielplanOffline.sh sourct bevorzugt mysetup.sh (statt setup.sh), wenn diese
# Datei im Programmverzeichnis liegt. Sie ersetzt setup.sh vollständig, muss
# also alle benötigten Variablen definieren.
#
# Diese Datei nach /srv/spielplanoffline/SpielplanOffline/mysetup.sh kopieren.

#------------------------------------------------------------------------
# Arbeits- und Ausgabeverzeichnisse
# HOMEDIR sollte zu ROOTDIR ($HOME) passen, das SpielplanOffline.sh an das
# awk-Skript übergibt (dort entsteht SpielplanOffline/tmp, /Fonts, /Output).
#------------------------------------------------------------------------
HOMEDIR="$HOME/SpielplanOffline"
TMPDIR="$HOMEDIR/tmp"
DEFAULTOUTDIR="$HOMEDIR/Output"   # wird vom Wrapper via outdir= überschrieben
odir="$DEFAULTOUTDIR"
history="$HOMEDIR/history.txt"

#------------------------------------------------------------------------
# Zusätzliche Programmpfade (unter Linux liegen die Tools im PATH -> leer).
# WGET/AWK/OCR bleiben ungesetzt und werden per `which` gefunden.
#------------------------------------------------------------------------
EXECPATH=""

# ImageMagick 7 (Debian 13/Ubuntu 25.04 aufwärts) installiert nur noch
# `magick`; SpielplanOffline.sh sucht ausschließlich nach `convert` und bricht
# sonst mit "FEHLER: ImageMagick convert nicht installiert" ab. Die
# Kommandozeile von `magick` ist an dieser Stelle identisch.
CONVERT="$(command -v convert || command -v magick || true)"

# Gültige UTF-8-Locale (setup.sh setzt en_ENG.UTF-8, die es nicht gibt).
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

#------------------------------------------------------------------------
# Auf dem Server gibt es kein "open" (macOS). backgroundprocessing=1 im
# Wrapper verhindert den Aufruf ohnehin; echo ist ein sicherer Fallback.
#------------------------------------------------------------------------
OPEN=echo
OPENPAR=""
ICONV=iconv
ICONVOPT=""
