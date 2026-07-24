#!/bin/bash
#
#Paramater file to start and run SpielpanOffline.sh
#Should be adapted to fit your own needs
#
#run with
#./MeinSpielplan.sh

BINDIR=`pwd`  # directory in dem die Programme von SpielplanOffline stehen - passe diesen Pfad an, wenn du dieses Script an einen anderen Ort kopierst."
echo "Starte $0"
echo "BINDIR = $BINDIR$"
cd $BINDIR

#------------------------------------------------------------------------
#Parameters for command line usage:
#(remove # to set new values)
#------------------------------------------------------------------------
#url='http://www.fussball.de/mannschaft/1-fc-koeln-1-fc-koeln-mittelrhein/-/saison/1920/team-id/011MIC49F0000000VTVG0001VTR8C1K7#!/'
url="http://www.fussball.de/mannschaft/1-fc-koeln-1-fc-koeln-mittelrhein/-/saison/1920/team-id/011MIC49F0000000VTVG0001VTR8C1K7#!/, http://www.fussball.de/mannschaft/spvg-frechen-1920-u21-spvg-frechen-20-mittelrhein/-/saison/1920/team-id/011MIBT4BS000000VTVG0001VTR8C1K7#!/"
#startdate=2019-08-01
#enddate=2019-07-31
#STYLE=EXCEL2
STYLE="ICS, EXCEL2"
#prefix=""
#NurAuswaertsspiele=0
#NurHeimspiele=0
#ignoriereAbgesagt=0
outdir=~/Desktop   # Ausgabe Directory
#csvfile=spielplan
csvfile="fckoeln, frechen20"
#------------------------------------------------------------------------

#Start Program -
if [  X$norun == X ]; then ./SpielplanOffline.sh -var $0; fi
