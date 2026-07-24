#!/bin/bash
#
#Creates a .csv or .ics date file for import into Google calendar, Outlook, or iCal from export of "Staffelspielplan" webpage from fussball.de
#Licence: Thanksware - free for non-commercial use, drop a note if you use it
#Date: July 2015, update Feb & July 2016, update July 2017, August 2019
#Author: Heino Falcke, h.falcke@astro.ru.nl
versionnumber=2.9
versionyear=2021
versionmonth=07
versionauthor="H. Falcke"
versionauthoremail="h.falcke@astro.ru.nl"
version="SpielplanOffline V$versionnumber ($versionauthor, $versionyear.$versionmonth)"
#
#
# Works only under MacOS and uses Pashua to create a GUI interface to fussball2csv2.0
# Could work under unix
#
# Parameters:
#  SpielplanOffline.sh -var MeinSpielplan.sh  - set input parameters from user input file
#  SpielplanOffline.sh url  - read this url and parameters from myinput.sh
#  SpielplanOffline.sh  - start GUI 

MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "--------------------------------------------------------------------------------"
echo Starte SpielplanOffline
echo "--------------------------------------------------------------------------------"

if [ -f ~/.profile ]; then
    source ~/.profile
fi

if [ -f ~/.bash_profile ]; then
    source ~/.bash_profile
fi

#Check for standard setup file or use user specified file
if [ -f mysetup.sh ]; then
    echo Reading system variables from user-defined file mysetup.sh
    source mysetup.sh
else
    echo Reading system variables from standard file setup.sh
    source setup.sh
fi

if [ "X$WGET" = X ]; then
    WGET=`which wget`
    echo WGET=$WGET
fi

if [ "X$AWK" = X ]; then
    AWK=`which gawk`
    echo AWK=$AWK
fi

if [ "X$OCR" = X ]; then
    OCR=`which tesseract`
    echo OCR=$OCR
fi

if [ "X$CONVERT" = X ]; then
    CONVERT=`which convert`
    echo CONVERT=$CONVERT
fi

#Find the the proper binary (e.g., in an HomeBrew installation), if not yet set
for d in $EXECPATH
do
    bindir=$d/bin
    echo Suche nach Programmen in $bindir

    if [ -x $bindir/wget ] && [ "X$WGET" = X ]; then
        WGET=$bindir/wget
        echo WGET=$WGET
    fi

    if [ -x $bindir/gawk ] && [ "X$AWK" = X ]; then
        AWK=$bindir/gawk
        echo AWK=$AWK
    fi

    if [ -x $bindir/tesseract ] && [ "X$OCR" = X ]; then
        OCR=$bindir/tesseract
        echo OCR=$OCR
    fi

    if [ -x $bindir/convert ] && [ "X$CONVERT" = X ]; then
        CONVERT=$bindir/convert
        echo CONVERT=$CONVERT
    fi
done

#echo Programme: AWK=$AWK, CONVERT=$CONVERT, OCR=$OCR

if [ "X$AWK" = X ] || [ ! -x $AWK ]; then
    echo FEHLER: gawk nicht installiert. Expected at this location: $AWK
    echo Passe [my]setup.sh an oder installiere das Paket, das mit SpielplanOffline geliefert wurde.
  exit 1
fi

if [ "X$CONVERT" = X ] ||[ ! -x $CONVERT ]; then
    echo FEHLER: ImageMagick convert nicht installiert. Expected at this location: $CONVERT
    echo Passe [my]setup.sh an oder installiere das Paket, das mit SpielplanOffline geliefert wurde.
    exit 1
fi

if [ "X$OCR" = X ] || [ ! -x $OCR ]; then
    echo FEHLER: OCR-Programm nicht installiert. Expected at this location: $OCR
    echo Passe [my]setup.sh an oder installiere das Paket, das mit SpielplanOffline geliefert wurde.
    exit 1
fi

if [ "X$outdir" == X ]; then outdir=$DEFAULTOUTDIR; fi

if [ ! -d $HOMEDIR ]; then  mkdir $HOMEDIR; fi
echo HOMEDIR=$HOMEDIR
if [ ! -d $TMPDIR ]; then  mkdir $TMPDIR; fi
echo TMPDIR=$TMPDIR
if [ ! -d $outdir ]; then  mkdir $outdir; fi
echo outdir=$outdir
if [ ! -f $history ]; then touch $history; fi

#------------------------------------------------------------------------
#Calculate default values/dates
#------------------------------------------------------------------------
currentdate=`date "+%Y-%m-%d"`
defaultenddate=`date -v+6m '+%Y-07-31'`
hist=( `cat $history` )
defaulturl=`tail -1 $history`

#------------------------------------------------------------------------
#Calculate unique Sequence Nr from date command
#------------------------------------------------------------------------
DefaultSequenceNR=`date +%s` #number of seconds since reference date. To be used
                      #as unique version number for calendarevent.

#------------------------------------------------------------------------
#MacOS specific part
#------------------------------------------------------------------------
if [ X$1 == X ]; #Programm started without url argument - start menu to get it
then
    echo "Programm started without weblink as argument - will start MacOS menu to get it."
    echo "For unix use provide command line argument and/or change parameters in script."

    # Include pashua.sh to be able to use the 2 functions defined in that file
    source "$MYDIR/pashua.sh"

    #Launch the Menu and set variables
    source "$MYDIR/pashua-menu.sh"
    
    if [ X$url == X ];
    then
        echo "Bitte kopiere einen Link in die erste Zeile des Menüs".
        exit 0
    fi

    if [ ! $cb -eq 0 ];
    then
        exit 0
    fi

    if [ "$heimausw" == "Nur Heimspiele" ];
    then
        NurHeimspiele=1;NurAuswaertsspiele=0;
    fi

    if [ "$heimausw" == "Nur Auswärtsspiele" ];
    then
        NurHeimspiele=0;NurAuswaertsspiele=1;
    fi

    #Prepend URL to history file, remmove duplicates and return max 5 lines
    echo "$url" | cat - $history | awk '/./{if (!($0 in lines)) {print $0; lines[$0]=1}}' | head -n 5 > $history.tmp; mv -f $history.tmp $history
else
    if [ "X$1" == "X-var" ] &&  [  -f "$2" ]; then
        echo Reading input paramters from user-defined file $2
        norun=1
        source "$2"
    elif [ -f myinput.sh ]; then
        echo Reading input paramters from user-defined file myinput.sh
        source myinput.sh
    else
        echo Reading input paramters from standard file input.sh
        source input.sh
    fi
    if [ "X$STYLE" = X ]; then STYLE=ICS,EXCEL2; fi
    if [ "X$startdate" = X ]; then startdate=$currentdate; fi
    if [ "X$enddate" = X ]; then enddate=$defaultenddate; fi
    if [ "X$NurAuswaertsspiele" = X ]; then NurAuswaertsspiele=0; fi
    if [ "X$NurHeimspiele" = X ]; then NurHeimspiele=0; fi
    if [ "X$ignoriereAbgesagt" = X ]; then ignoriereAbgesagt=0; fi
fi
#------------------------------------------------------------------------

# extension=csv
# if [ X$STYLE == XTEXT ]; then extension=txt; fi
# if [ X$STYLE == XICS ]; then extension=ics; fi
# outfile=spielplan.$extension

cd $MYDIR

if [ "X$SequenceNR" = X ]; then SequenceNR=$DefaultSequenceNR; fi

echo "--------------------------------------------------------------------------------"
echo "Sequence Nr.: " $SequenceNR
$AWK -f runscript.awk -v ROOTDIR=$HOME -v url="$url" -v StartDatum=$startdate -v EndDatum=$enddate -v outdir="$outdir" -v csvfile="$csvfile" -v style="$STYLE" -v Prefix="$prefix" -v SequenceNR=$SequenceNR -v OS=MAC -v AWK=$AWK -v CONVERT=$CONVERT -v OCR=$OCR -v WGET=$WGET -v NurHeimspiele=$NurHeimspiele -v NurAuswaertsspiele=$NurAuswaertsspiele -v ignoriereAbgesagt=$ignoriereAbgesagt runscript.awk

# if [ X$STYLE == XCALENDAR ];
# then
#     echo "Dieses CSV-Format kann in Google Calendar importiert werden."
# fi

# if [ X$STYLE == XICS ];
# then
#     echo "Das ICS-Format kann in fast jedes Kalenderprogramm direkt importiert werden. Es wird jetzt automatisch geöffnet und in iCal eingelesen. Du musst dort nur noch den Kalender auswählen in dem die Termine erscheinen sollen. Um sie zu löschen kannst du die Datei cancel-$outfile öffnen (experimentell!)"
# fi

#if [ ! -d $outdir ]; then  mkdir $outdir; fi
# if [ X$STYLE == XEXCEL ];
# then
#     $ICONV $ICONVOPT $TMPDIR/$outfile > $outdir/$outfile
#     echo "Das CSV-Format kann in Excel über die Importfunktion eingelesen werden."
# else
#cp -f $TMPDIR/$outfile $outdir/$outfile
#fi

echo "--------------------------------------------------------------------------------"
echo Fertig! Spielpläne steht jetzt im Verzeichnis $outdir
echo "--------------------------------------------------------------------------------"
echo Diese Software ist kostenlos zum nichtkommerziellen Gebrauch freigegeben.
echo Ich bitte aber um ein kurzes Feedback, wenn sie erfolgreich eingesetzt wurde.
echo Das hift mir bei der Entscheidung, ob die Software weiter gepflegt werden soll,
echo "da Fussball.de sich jedes Jahr ändert ... ($versionauthoremail)"
echo " "
echo $version

#Öffne das Directory im Finder 
if [ X$backgroundprocessing != X1 ];
then
    $OPEN $outdir
fi

#if [ X$STYLE == XICS ];
#then
#    $AWK -f cancel.awk $outdir/$outfile > $outdir/cancel-$outfile
#    $OPEN $outdir/$outfile
#else
#    $OPEN $OPENPAR $outdir/$outfile
#    $OPEN $outdir
#fi
