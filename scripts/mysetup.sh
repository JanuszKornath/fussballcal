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
# WGET/AWK/OCR/CONVERT bleiben ungesetzt und werden per `which` gefunden.
#------------------------------------------------------------------------
EXECPATH=""

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
