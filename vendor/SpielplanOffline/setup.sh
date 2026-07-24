#Setup file that will be sourced by SpielpanOffline.sh Should be
#copied to mysetup.sh and then adapted to fit your own system.
#mysetup.sh will take prescedence over setup.sh

#------------------------------------------------------------------------
#Direcrories where files are stored
#------------------------------------------------------------------------
HOMEDIR=$HOME/SpielplanOffline
TMPDIR=$HOMEDIR/tmp
#DEFAULTOUTDIR=$HOME/Desktop   # Defaultwert für das Ergebnisdirectory outdir 
DEFAULTOUTDIR=$HOMEDIR/Output   # Defaultwert für das Ergebnisdirectory outdir 
odir=$DEFAULTOUTDIR #Output directory
history="$HOMEDIR/history.txt"
#------------------------------------------------------------------------
echo PATH = $PATH

#------------------------------------------------------------------------
#Directories where additional executables can be found
#------------------------------------------------------------------------
EXECPATH="/opt/homebrew /opt/local"
export LC_ALL=en_ENG.UTF-8  
export LANG=en_ENG.UTF-8

#------------------------------------------------------------------------
#Path to programs used in the script - adapt if needed.
#(needs full path to the executable binary)
#------------------------------------------------------------------------
#BINDIR=/opt/macports-portable/bin # Example path
#AWK=$BINDIR/gawk  # uncomment if you want to set manually
#CONVERT=$BINDIR/convert # uncomment if you want to set manually
#OCR=$BINDIR/tesseract # uncomment if you want to set manually
#If above are not set, EXECPATH will be searched for those programs
#------------------------------------------------------------------------
#WGET=wget
OPEN=open   # set to echo in Unix ?
OPENPAR="-a textedit.app"
ICONV=iconv # set to cat in Unix ?
ICONVOPT="-f utf-8 -t mac" # set to "" in Unix ? 
#------------------------------------------------------------------------

