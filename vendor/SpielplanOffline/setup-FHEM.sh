#Setup file that will be sourced by SpielpanOffline.sh Should be
#copied to mysetup.sh and then adapted to fit your own system.
#mysetup.sh will take prescedence over setup.sh

#Setup file for House automization system FHEM running on Raspberry PI
#File thanks to user Sille
#See: https://forum.fhem.de/index.php/topic,56494.0.html

#Set path to work with MacPort!
export PATH=/usr/bin:/usr/sbin:$PATH

#------------------------------------------------------------------------
#Direcrories where files are stored
#------------------------------------------------------------------------
HOMEDIR=/opt/fhem/SpielplanOffline
TMPDIR=$HOMEDIR/tmp
DEFAULTOUTDIR=$HOMEDIR/Ergebnis   # Defaultwert für das Ergebnisdirectory outdir
odir=$DEFAULTOUTDIR #Output directory
history="$HOMEDIR/history.txt"
#------------------------------------------------------------------------

#------------------------------------------------------------------------
#Path to programs used in the script - adapt if needed.
#------------------------------------------------------------------------
AWK=/usr/bin/gawk
#CONVERT=/opt/ImageMagick/bin/convert
CONVERT=/usr/bin/convert
WGET=wget
OCR=tesseract
OPEN=echo   # set to echo in Unix ?
OPENPAR="-a textedit.app"
ICONV=cat # set to cat in Unix ?
ICONVOPT="" # set to "" in Unix ?
#------------------------------------------------------------------------

#------------------------------------------------------------------------
#Calculate unique Sequence Nr from date command
#------------------------------------------------------------------------
SequenceNR=`date +%s` #number of seconds since reference date.
