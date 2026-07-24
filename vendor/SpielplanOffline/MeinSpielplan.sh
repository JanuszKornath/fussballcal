#!/bin/bash
#
#V2.9 07/2021
#Parameter file to start and run SpielpanOffline.sh
#Should be adapted to fit your own needs
#
#run with
#./MeinSpielplan.sh

BINDIR=`pwd`  # directory in dem die Programme von SpielplanOffline stehen - passe diesen Pfad an, wenn du dieses Script an einen anderen Ort kopierst."
echo "Starte $0"
echo "BINDIR = $BINDIR$"
cd $BINDIR

#------------------------------------------------------------------------
#Parameter zur Ausführung des Scripts:
#.....................................
#(Entferne das # am Anfang, um einen Wert zu setzen, sonst macht das
# Programm es automatisch für dich oder fragt dich)
#------------------------------------------------------------------------

#URL
#---------------------
#Gebe hier den Link von Fussball.de zu deiner Mannschaft ein
url='http://www.fussball.de/mannschaft/1-fc-koeln-1-fc-koeln-mittelrhein/-/saison/2122/team-id/011MIC49F0000000VTVG0001VTR8C1K7#!/'
url='https://www.fussball.de/mannschaft/spvg-frechen-1920-u21-spvg-frechen-20-mittelrhein/-/saison/2122/team-id/023R7NU5V8000000VS548984VVIKHNJO#!/'
url='https://www.fussball.de/mannschaft/1-fc-kaiserslautern-u19-1-fc-kaiserslautern-suedwest/-/saison/2122/team-id/011MIAM2SO000000VTVG0001VTR8C1K7#!/'

#Es können übrigens auch mehrere Mannschaften sein 
#url="http://www.fussball.de/mannschaft/1-fc-koeln-1-fc-koeln-mittelrhein/-/saison/1920/team-id/011MIC49F0000000VTVG0001VTR8C1K7#!/, http://www.fussball.de/mannschaft/spvg-frechen-1920-u21-spvg-frechen-20-mittelrhein/-/saison/1920/team-id/011MIBT4BS000000VTVG0001VTR8C1K7#!/"

#Ausgabeformat und Ort
#---------------------
STYLE="ICS, EXCEL2"   #Calendar und Excel-Format werden beide ausgegeben 

#outdir=~/SpielplanOffline/Output   # Ausgabe Directory
#csvfile="fckoeln, frechen20"  # Damit kann man eigene Namen für die Ausgabedatei definieren

#Start- und Enddatum
#---------------------
#startdate=2021-07-01
#enddate=2022-06-31

#Weitere Parameter
#---------------------
#prefix=""            # Text vor jeder Begegnung, wenn man z.B. die Ausgabe mit einem anderen Programm sortieren möchte
#NurAuswaertsspiele=0
#NurHeimspiele=0
#ignoriereAbgesagt=0
#backgroundprocessing=1  # Setze =1, um zu verhindern, dass am Ende des Scripts das Directory geöffnet wird

#Alte Version
#---------------------
#Benutze die nächten Zeilen, für das selbe Verhalten, wie vor Version 2.8 
#csvfile=spielplan  #
#outdir=~/Desktop   # Ausgabe Directory
#STYLE=ICS          # 

#------------------------------------------------------------------------
#Ende Eingabe der Parameter
#------------------------------------------------------------------------

#Starte Programm - diese Zeile muss hier bleiben
if [  X$norun == X ]; then ./SpielplanOffline.sh -var $0; fi
