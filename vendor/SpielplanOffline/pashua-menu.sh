#------------------------------------------------------------------------
#Menu used for SpielplanOffline - will be sourced by shell script
#------------------------------------------------------------------------

# Define what the dialog should be like
# Take a look at Pashua's Readme file for more info on the syntax

conf="
# Set window title
*.title = Wilkommen bei SpielplanOffline


# Introductory text
txt.type = text
txt.default = SpielplanOffline erlaubt es sich einen Spielplan einer Fußballmanschaft oder eines Fußballvereins von Fussball.de herunterzuladen und in ein Textformat zu konvertieren, dass man dann in ical, Outlook, Excel oder Google Calendar einlesen kann. Wie es funktionert: Gehe zu Fussball.de, suche deine Mannschaft oder deinen Verein und gehe auf die enstprechende Wereinsseite oder Mannschaftsseite von Fussball.de. Kopiere den Link zu dieser Seite dann in das Textfeld links und drücke OK. Das ICS-Format kann in iCal oder Outlook importiert werden.
txt.height = 276
txt.width = 450
txt.x = 0
txt.y = 290
txt.tooltip = SpielplanOffline - Erklärung

signature.type = text
signature.default = $version
signature.height = 10
signature.width = 128
signature.x = 470
signature.y = 270
signature.tooltip = SpielplanOffline - Erklärung

img.type = image
img.x = 460
img.y = 290
img.maxwidth = 128
img.tooltip = SpielplanOffline Logo
img.path = falcon2.png

# For tests
# url.default = http://www.fussball.de/mannschaft/bw-koenigsdorf-tus-bw-koenigsdorf-1900-ev-mittelrhein/-/saison/1516/team-id/011MIAU23K000000VTVG0001VTR8C1K7#!/section/mediastream

url.type = combobox
url.label = Link zur Vereins/Mannschaftsseite auf Fussball.de 
url.default = ${hist[0]}
url.option = ${hist[1]}
url.option = ${hist[2]}
url.option = ${hist[3]}
url.option = ${hist[4]}
url.width = 600
url.tooltip = Wähle Link aus der Liste oder kopiere einen neuen in das Feld
url.x = 0
url.y = 230

# Add a filesystem browser
odir.type = openbrowser
odir.label = Ausgabeverzeichnis
odir.default = $DEFAULTOUTDIR
odir.filetype=directory
odir.width=310
odir.tooltip = Ausgabeverzeichnis

# Define radiobuttons
#rb.type = radiobutton
#rb.label = Example radiobuttons
#rb.option = Radiobutton item #1
#rb.option = Radiobutton item #2
#rb.tooltip = This is an element of type “radiobutton”

# # Add a popup menu
# saison.type = popup
# saison.label = Saison
# saison.width = 310
# saison.option = 15/16
# saison.option = 16/17
# saison.option = 17/18
# saison.option = 18/19
# saison.default = 15/16
# saison.tooltip = Spielsaison (jj/jj)

startdate.x=0
startdate.y=170
startdate.type = date
startdate.label = Start Datum
startdate.tooltib = Erstes Datum der Spieltermine
startdate.default = $currentdate
startdate.time = 0
startdate.textual = 1

enddate.x=120
enddate.y=170
enddate.type = date
enddate.label = Enddatum
enddate.tooltib = Letztes Datum der Spieltermine
enddate.default = $defaultenddate
enddate.time = 0
enddate.textual = 1

# Add a popup menu
STYLE.x=240
STYLE.y=170
STYLE.type = popup
STYLE.label = Ausgabeformat 
STYLE.width = 310
STYLE.option = CALENDAR
STYLE.option = ICS
STYLE.option = ICSCSV
STYLE.option = EXCEL
STYLE.option = EXCEL2
STYLE.option = TEXT
STYLE.default = ICS
STYLE.tooltip = Ausgabeformat (ICS kann direkt in Outlook oder iCal importiert werden) 

# Add a text field
prefix.type = textfield
prefix.label = Prefix
prefix.width = 150
prefix.tooltip = Text der als Prefix for der Begegenung steht (z.B. Fußball)
prefix.x = 0
prefix.y = 110

#
heimausw.type = radiobutton
heimausw.tooltip = Bestimmt ob nur Heim oder nur Auswärtspiele oder beide ausgegeben werden
heimausw.option = Nur Heimspiele
heimausw.option = Nur Auswärtsspiele
heimausw.option = Heim- und Auswärtsspiele
heimausw.default = Heim- und Auswärtsspiele
heimausw.y=92
heimausw.x=190

ignoriereAbgesagt.type = checkbox
ignoriereAbgesagt.label = Ignoriere abgesagte Spiele
ignoriereAbgesagt.tooltip = Abgesagte Spiele werden nicht ausgegeben, werden dann im Kalender aber u.U. auch nicht gelöscht!
ignoriereAbgesagt.y=110
ignoriereAbgesagt.x=400

# Add 2 checkboxes
#chk.rely = -18
#chk.type = checkbox
#chk.label = Pashua offers checkboxes, too
#chk.tooltip = This is an element of type “checkbox”
#chk.default = 1
#chk2.type = checkbox
#chk2.label = But this one is disabled
#chk2.disabled = 1
#chk2.tooltip = Another element of type “checkbox”

# Add a cancel button with default label
cb.type = cancelbutton
cb.tooltip = Abbrechen

db.type = defaultbutton
db.tooltip = This is an element of type “defaultbutton” (which is automatically added to each window, if not included in the configuration)
"

pashua_run "$conf" .

# echo "Pashua created the following variables:"

# echo "  url  = $url"
# echo "  cb  = $cb"
# echo "  STYLE = $STYLE"
# echo "  saison = $saison"
# echo "  odir  = $odir"

# echo ""

# echo DIR = $MYDIR

#exit 0
