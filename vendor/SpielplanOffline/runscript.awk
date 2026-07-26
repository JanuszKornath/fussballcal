#Download a Spielplan from Fussball.de
#License: Thanksware - free for non-commercial use, drop a note if you use it
#Version: 2.8
#Date: July 2015, update Feb 2016, 30 July 2016, July, August 2017, August 2019
#Author: Heino Falcke, 50226 Frechen, h.falcke@astro.ru.nl
#Program uses tesseract, ImageMagick convert, portable perl, gnu awk, - please respect the relevant licenses
#
# Parameters:
# -v url="http://www.fussball.de/..."  - URL to a club or team webpage on fussball.de
# -v StartDatum=2015-08-01 - Startdatum der Termine (überschreibt Saison)
# -v EndDatum=2015-08-01 - Enddatum der Termine (überschreibt Saison)
# -v OS=MAC - Betriebssystem (MAC,WIN32,WIN64)
# -v spielplanfile=spielplan.html (removed)
# -v vereinssfile=verein.html (removed)
# -v ROOTDIR=/Users/falcke
# -v OFFLINE=1 Do not execute WGET, but use latest downloaded webpage
# -v csvfile=Dateiname     - Name der Datei mit dem Output im csv Format, will be created automatically if not given
# -v outdir=/Users/falcke  - Directory where to place outputfile if csvfile is not given (ROOTDIR/SpielplanOffline/Output by default)
# -v style=style           - Output-Style: EXCEL, CALENDAR, ICS  
# -v Prefix="Text"         - Ein Schluesselwort/Prefix, dass man vor jedes Spiel setzen kann (z.B. "Fussball", wenn man Kalender mit mehreren Sportarten hat)
# -v SequenceNR            - seconds since 1970 - should always be higher, whenever a new .ics version is created and imported into a calendar
# -v NurHeimspiele=1       - Gebe nur Heimspiele aus
# -v NurAuswaertsspiele=1  - Gebe nur Ausw�rtsspiele aus
# -v ignoriereAbgesagt=1   - Ignoriere abgesagte Spiele im Output
#
# Beispiel:
#gawk -f runscript.awk -v ROOTDIR="C:\\Users\\Heino Falcke" -v url="http://www.fussball.de/mannschaft/bw-koenigsdorf-tus-bw-koenigsdorf-1900-ev-mittelrhein/-/saison/1516/team-id/016J70KIOO000000VV0AG811VSBH97M6#!/section/stage" -v StartDatum=2015-12-31 -v EndDatum=2016-06-30 -v OS=WIN64  -v style=ICS -v Prefix=""  runscript.awk
#-v OFFLINE=1
#(Windows)
#
#MAC OS:
# /opt/local/bin/gawk -f runscript.awk -v ROOTDIR=/Users/falcke -v url='http://www.fussball.de/mannschaft/spvg-frechen-1920-ii-spvg-frechen-20-mittelrhein/-/saison/0201KOJ55S000000VS548985VU1T928D/team-id/011MIBT4BS000000VTVG0001VTR8C1K7#!/' -v StartDatum=2019-08-01 -v EndDatum=2020-06-30 -v style=ICS -v OFFLINE=1 -v csvfile=~/Desktop/spielplan.ics runscript.awk
#
# /opt/local/bin/gawk -f runscript.awk -v ROOTDIR=/Users/falcke -v url='http://www.fussball.de/mannschaft/spvg-frechen-1920-ii-spvg-frechen-20-mittelrhein/-/saison/0201KOJ55S000000VS548985VU1T928D/team-id/011MIBT4BS000000VTVG0001VTR8C1K7#!/' -v StartDatum=2019-08-01 -v EndDatum=2020-06-30 -v style='ICS,EXCEL2' -v outdir=~/Desktop runscript.awk
#
# /opt/local/bin/gawk -f runscript.awk -v ROOTDIR=/Users/falcke -v url='http://www.fussball.de/mannschaft/spvg-frechen-1920-u21-spvg-frechen-20-mittelrhein/-/saison/1920/team-id/011MIBT4BS000000VTVG0001VTR8C1K7#!/,http://www.fussball.de/mannschaft/1-fc-koeln-1-fc-koeln-mittelrhein/-/saison/1920/team-id/011MIC49F0000000VTVG0001VTR8C1K7#!/,http://www.fussball.de/mannschaft/spvg-frechen-1920-spvg-frechen-20-mittelrhein/-/saison/1920/team-id/011MIEUJLG000000VTVG0001VTR8C1K7#!/' -v StartDatum=2019-08-01 -v EndDatum=2019-09-30 -v style='ICS,EXCEL2' runscript.awk



#convert -background white -fill black -font '/Users/falcke/SpielplanOffline/Fonts/font-mhgtx6b0.ttf' -pointsize 40 -kerning 9 -interword-spacing 27 label:@'/Users/falcke/SpielplanOffline/tmp/utfcodes-mhgtx6b0.mult.1.txt' '/Users/falcke/SpielplanOffline/tmp/image-mhgtx6b0.1.png'

# Achtung: Der inputfile ist nur ein Dummy-File, der nicht wirklich gelesen wird.

BEGIN{
    OEXT["EXCEL"]="csv"
    OEXT["EXCEL2"]="csv"
    OEXT["TEXT"]="txt"
    OEXT["CALENDAR"]="csv"
    OEXT["ICS"]="ics"
    OEXT["ICSCSV"]="csv"

    if (!OS) OS="MAC"
    OSFAMILY=substr(OS,1,3)

    if (!SequenceNR) SequenceNR=0
    if (!MaxNumberOfRetries) MaxNumberOfRetries=3 # How often to try to reload webpage until no error
    
    RENAME="mv -f"; COPY="cp -f"; MOVE="mv -f"; CAT="cat"; DEL="rm -f"

    #OS-specific commands and definitions:
    QUOTE = "'"
    DIRSEP="/"
    DOT="."
    PIPE=" > "
    PIPEC=" | "
    APPEND=" >> "

    WGETOPT = "-q -O"

    if (OSFAMILY=="WIN") {
        QUOTE = "\""; DIRSEP="\\"
        RENAME="ren"; COPY="copy"; MOVE="move"; CAT="type"; DEL="del /Q"

        if (!CONVERT) CONVERT="convert"
        if (!AWK) AWK="gawk"
        if (!OCR) OCR="tesseract"
        if (!PERL) PERL="perlbin\\perl.exe"
        if (OS=="WIN64") {WGET = "wget64"} else {WGET = "wget"}
        OCROPT=" -psm 6 " # Note used dirty trick here, renamed german traineddata to eng. 
    } else { #MACOS
        if (!WGET) WGET = "wget"
        if (!CONVERT) CONVERT="convert" #/opt/ImageMagick/bin/
        if (!AWK) AWK="gawk"
        if (!OCR) OCR="tesseract"
        if (!PERL) PERL="perl"
        OCROPT=" -l deu --psm 6 "
    }

    if (OFFLINE) WGET="echo"
    
    HOMEDIR=ROOTDIR DIRSEP "SpielplanOffline"
    tmpdir=HOMEDIR DIRSEP "tmp"
    fontdir=HOMEDIR DIRSEP "Fonts"
    if (!outdir) outdir=HOMEDIR DIRSEP "Output"

    TESTMAKEDIR(HOMEDIR)
    TESTMAKEDIR(tmpdir)
    TESTMAKEDIR(fontdir)
    TESTMAKEDIR(outdir)
                
    ext="ttf"
    pointsize=40 #font size generated in pixmap for OCR
    kerning=9 #defines separation between letters in the pixmap image
    interwordspacing=27 #defines separation between words in the pixmap image
     
    True=1
    False=0
    verbose=True

    #check if there are multiple urls or output styles 
    nurl=split(url,urls,"[ ,] *")
    nstyle=split(style,styles,"[ ,] *")
    print "Input:",nurl,"urls and",nstyle,"output styles." 
    print url
    if (csvfile) ncsv=split(csvfile,csvfiles,"[ ,] *")
    
    for (urli=1;urli<=nurl;urli++) {
        if (urli>1) print " "
        url0=urls[urli]
        
        NumberOfRetries=MaxNumberOfRetries
        decodeerror=1

        #Check URL
        start=index(url0,"fussball.de/")

        #Remove everything until fussball.de
        shorturl=substr(url0,start+length("fussball.de/"))
        nurlwords=split(shorturl,urlwords,"/")

        #Check if URL is long enough and did contain fussball.de
        if (!start || nurlwords<2) {
            print "Weblink",url0,"hat falsches Format! Bitte Mannschafts, Staffel oder Clubseite von Fussball.de kopieren und eingeben."
            exit 1
        }

        Verein = urlwords[2]

        spielplanfile=tmpdir DIRSEP "spielplan-" Verein ".html"
        vereinsfile=tmpdir DIRSEP "verein-" Verein ".html"
        #print "Spielplanfile = " spielplanfile
        #print "Vereinsfile = " vereinsfile
	
        originalspielplanfile=spielplanfile
        sub("[.][a-zA-Z]+$","-original.html",originalspielplanfile)
        spielplanfiletmp=spielplanfile DOT "tmp"
   
            

    
#    http://www.fussball.de/spieltag/landesliga-staffel-1-mittelrhein-landesliga-herren-saison1617-mittelrhein/-/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/section/stage

#    http://www.fussball.de/spieltag/landesliga-staffel-1-mittelrhein-landesliga-herren-saison1617-mittelrhein/-/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/section/stage

    #http://www.fussball.de/spielplan.druck/-/datum-bis/2017-07-31/datum-von/2017-05-16/max/999/mode/PRINT/show-venues/true/staffel/01SF5N3EI8000003VS54898DVVGA4426/type/-1#!/

    #http://www.fussball.de/spielplan.druck/-/datum-bis/2017-06-30/datum-von/2016-07-01/max/999/mode/PRINT/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/
    
#        print urlwords[1], urlwords[4]
        if (tolower(urlwords[1])=="mannschaft") {usemannschaft=True; useverein=False; usestaffel=False}
        else if (tolower(urlwords[1])=="verein") {usemannschaft=False; useverein=True; usestaffel=False}
        else if (tolower(urlwords[1])=="spieltag" && urlwords[4]=="staffel") {usemannschaft=False; useverein=False; usestaffel=True}
        else {
            print "Weblink",url0,"hat falsches Format! Das scheint weder eine Mannschafts noch eine Clubseite von fussball.de zu sein!"
            exit 2
        }

    #Get Vereins und MannschaftsID
    #Download webpage of team with wget and get Club ID from the html code
        if (match(shorturl,"/team-id/[0-9A-Z]+")) {
            MannschaftsID=substr(shorturl,RSTART+9,RLENGTH-9)
	    print "MannschaftsID=" MannschaftsID
            if (verbose) print "Hole VereinsID von fusball.de ..."
            print WGET " " WGETOPT " " QUOTE vereinsfile QUOTE " " QUOTE url0 QUOTE 
            print AWK " -f getid.awk " QUOTE vereinsfile QUOTE 
	    WGET " " WGETOPT " " QUOTE vereinsfile QUOTE " " QUOTE url0 QUOTE | getline status
            AWK " -f getid.awk " QUOTE vereinsfile QUOTE | getline VereinsID
        }
        if (match(shorturl,"/id/[0-9A-Z]+")) VereinsID=substr(shorturl,RSTART+4,RLENGTH-4)
        if (match(shorturl,"/staffel/[0-9A-Z].*[A-Z]")) StaffelID=substr(shorturl,RSTART+9,RLENGTH-9)

        if (! VereinsID && ! StaffelID ) {
            print "Irgendwas ist falsch - ich konnte weder Vereins noch Staffel ID finden - Sorry."
            exit 1
        }

        f=HOMEDIR DIRSEP "lasturl.txt"; print url0 > f; close(f) 
    
        if (verbose) print "------------------------------------------------------------------------"
        if (verbose) print "Verein & Team :",Verein
        if (verbose) print "Vereins ID    :",VereinsID
        if (verbose) print "Mannschafts ID:",MannschaftsID    
        if (verbose) print "Staffel ID:",StaffelID    
        if (!StartDatum) {StartDatum = "20" yy1 "-08-01"} 
        if (!EndDatum) {EndDatum = "20" yy2 "-07-31"} 

        #http://www.fussball.de/spielplan/landesliga-staffel-1-mittelrhein-landesliga-herren-saison1617-mittelrhein/-/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/section/matchplan
        #http://www.fussball.de/spielplan.druck/-/datum-bis/2017-06-30/datum-von/2016-07-01/max/999/mode/PRINT/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/

        #OK http://www.fussball.de/spielplan.druck/-/datum-bis/2017-06-30/datum-von/2016-07-01/max/999/mode/PRINT/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/
        #XK http://www.fussball.de/spielplan.druck/-/datum-bis/2018-07-31/datum-von/2017-05-16/max/999/mode/PRINT/staffel/01SF5N3EI8000003VS54898DVVGA4426-G#!/
    
        if (StaffelID) spielplanurl="http://www.fussball.de/spielplan.druck/-/datum-bis/" EndDatum "/datum-von/" StartDatum "/max/999/mode/PRINT/show-venues/true/staffel/" StaffelID "#!/"
        else if (MannschaftsID) spielplanurl="http://www.fussball.de/vereinsspielplan.druck/-/datum-bis/" EndDatum "/datum-von/" StartDatum "/id/" VereinsID "/max/999/mode/PRINT/show-venues/true/team-id/" MannschaftsID "/type/-1#!/"
        else spielplanurl="http://www.fussball.de/vereinsspielplan.druck/-/datum-bis/" EndDatum  "/datum-von/"  StartDatum  "/id/" VereinsID "/max/999/mode/PRINT/show-venues/true/type/-1#!/"

        if (verbose) print "Input URL     :",url0
        if (verbose) print "Spielplan URL :",spielplanurl
        if (verbose) print "Spielplanfile :",spielplanfile
        if (verbose) print "Zeitraum      :",StartDatum,"-",EndDatum
        if (verbose) print "------------------------------------------------------------------------"
    
        if (verbose) print "Lade Daten von Fussball.de."

        #run mutiple times if there is an error in the decoding 
        while (decodeerror && NumberOfRetries) {
            if (NumberOfRetries < MaxNumberOfRetries) {print "\nRETRY! Versuche es noch einmal von vorne!"}
            --NumberOfRetries
		
            COMMAND=WGET " " WGETOPT " " QUOTE originalspielplanfile QUOTE " " QUOTE spielplanurl QUOTE
            COMMAND | getline status; close(COMMAND)

            COMMAND=COPY " " QUOTE originalspielplanfile QUOTE " " QUOTE spielplanfile QUOTE
            COMMAND | getline status; close(COMMAND)
	
            print "Download von " originalspielplanfile " abgeschlossen."
	
            COMMAND=AWK " -f extractfontcodes.awk -v tmpdir=" quote(tmpdir DIRSEP) " " QUOTE originalspielplanfile QUOTE
            COMMAND | getline status; close(COMMAND)
#	 print "Fontnumbers =" status

            #extractfontcodes identifies fonttables used by the webpage and returns their names
            #also creates lots of other files ...
	
            split(status,fontnumbers,",")

            for (i in fontnumbers) {
                fn=fontnumbers[i]
                print "Fontnumber:",fn
                fontroot=fontdir DIRSEP "font-" fn
                fontfile=fontroot DOT ext
                perlcodes=tmpdir DIRSEP "utfcodes-" fn DOT "perl"
                utfcodes=tmpdir DIRSEP "utfcodes-" fn DOT "txt"
                ocrroot=tmpdir DIRSEP "ocr-" fn
                ocrfile=ocrroot DOT "txt"
                codetable=tmpdir DIRSEP "codetable-" fn DOT "txt"
                hexcodes=tmpdir DIRSEP "hexcodes-" fn DOT "txt"
                hexcodesmult=tmpdir DIRSEP "hexcodes-" fn DOT "mult" DOT "txt"

                DELETEFILE(ocrfile)
                #DELETEFILE("x")
		
                #download font
                COMMAND=WGET " " WGETOPT " " QUOTE fontfile QUOTE " " QUOTE "http://www.fussball.de/export.fontface/-/format/" ext "/id/" fn "/type/font" QUOTE
                COMMAND | getline status; close(COMMAND)

#		 creates utf characters in a text file using a perl code generated by extractfontcodes.awk 
#		 print "perlcodes=" perlcodes
                COMMAND=PERL " " QUOTE perlcodes QUOTE PIPE QUOTE utfcodes QUOTE
                COMMAND | getline status; close(COMMAND)

                COMMAND=AWK " -f nlines.awk " QUOTE utfcodes QUOTE 
                COMMAND | getline status; close(COMMAND)
		
                maxpagelen=50 # Maximum number of lines per page for OCR
                #print "nlines=",status
                nlines=status; if (nlines<1) {nlines=1} # total number of lines to be coverted
                npages=int((nlines-1)/maxpagelen+1) # number of pages/images to be created and read by OCR
                pagelen=int(nlines/npages+0.5) # number of lines per page

                # this file contains the utf hexcodes for each character which will be compared against the OCR output		   
                # repeats the same line multiple times, in order to have more words and improve OCR quality
#		 print "hexcodes=" hexcodes,"hexcodesmult=" hexcodesmult
                COMMAND=AWK " -f triple.awk " QUOTE hexcodes QUOTE PIPE QUOTE hexcodesmult QUOTE
                COMMAND | getline status; close(COMMAND)
		
                # now create an image based on the UTF codes, feed it into the
                # OCR software and return the clear text in an ASCII text file
                # to avoid too large image files, the input text is split into
                # multiple pages if needed
                #LOKALER PATCH (fussballcal): Die Seitenlaenge ist jetzt
                #selbstregelnd. Fussball.de nutzt inzwischen Fonts, deren
                #Zeilenhoehe so gross ist, dass ImageMagick bei einer vollen
                #Seite mit "width or height exceeds limit" abbricht (Grenze aus
                #policy.xml, per Vorgabe 32KP). Es entsteht dann kein Bild,
                #die OCR liefert nichts und die Code-Tabelle bleibt leer --
                #also wieder keine Datums-/Zeitangaben. Schlaegt das Rendern
                #fehl, wird die Seite halbiert und erneut versucht, statt eine
                #feste Zeilenzahl zu raten.
                j=0
                startline=1
                while (startline<=nlines) {

                    endline=startline+pagelen-1
                    if (endline>nlines) endline=nlines
                    j++
                    print "Creating OCR Image #" j " with maximally " pagelen " lines from line " startline " to " endline

                    # UTF-encoded file which contains the characters to be decoded via OCR
                    utfcodesmult=tmpdir DIRSEP "utfcodes-" fn DOT "mult" DOT j DOT "txt"

                    #png image containing the current page for OCR
                    image=tmpdir DIRSEP "image-" fn DOT j DOT "png"

                    #Text file containing the output of the OCR program
                    ocrrootpageN=ocrroot DOT j
                    ocrfilepageN=ocrrootpageN DOT "txt"

                    # repeats the same line mutliple times, in order to have more words and improve OCR quality
                    # also split utf file into multiple pages
#		 print "utfcodes=" utfcodes,"utfcodesmult=" utfcodesmult
                    COMMAND=AWK " -f triple.awk -v startline=" startline " -v endline=" endline " " QUOTE utfcodes QUOTE PIPE QUOTE utfcodesmult QUOTE
                    COMMAND | getline status; close(COMMAND)
	
                    #print "Imagefile:",image
                    #print "Fontfile:",fontfile
		
                    #convert utfcodes in page to an image which is fed to ocr software
                    #LOKALER PATCH (fussballcal): Debian/Ubuntu verbieten in
                    #/etc/ImageMagick-*/policy.xml per <policy domain="path"
                    #rights="none" pattern="@*"/> das indirekte Einlesen von
                    #Dateien, d.h. "label:@datei" scheitert dort mit
                    #"operation not allowed by the security policy". Ohne Bild
                    #gibt es keine OCR-Ausgabe, keine Code-Tabelle und damit
                    #keine entschluesselten Datums-/Zeitangaben. Unter Unix
                    #wird der Text deshalb per Kommandosubstitution direkt als
                    #Argument uebergeben; das Ergebnis von $(...) wird in
                    #doppelten Anfuehrungszeichen nicht erneut expandiert.
                    if (OSFAMILY=="WIN") labelarg="label:@" QUOTE utfcodesmult QUOTE
                    else labelarg="label:\"$(cat " QUOTE utfcodesmult QUOTE ")\""
                    #Ein Bild aus einem frueheren Lauf wuerde sonst faelschlich
                    #als Erfolg durchgehen.
                    DELETEFILE(image)
                    COMMAND=CONVERT " -background white -fill black -font " QUOTE fontfile QUOTE " -pointsize " pointsize " -kerning " kerning " -interword-spacing " interwordspacing " " labelarg " " QUOTE image QUOTE
                    COMMAND | getline status; close(COMMAND)
                    #print "Command:",COMMAND

                    if (!FILEEXISTS(image)) {
                        #Untergrenze 2: triple.awk behandelt endline<=startline
                        #als "nicht aufteilen" und wuerde bei einer Seitenlaenge
                        #von 1 wieder die komplette Datei ausgeben.
                        if (pagelen>2) {
                            pagelen=int(pagelen/2); if (pagelen<2) pagelen=2
                            print "Bild konnte nicht erzeugt werden - halbiere die Seitenlaenge auf " pagelen " Zeilen und versuche es erneut."
                            j--
                            continue
                        }
                        #Selbst zwei Zeilen lassen sich nicht rendern. Weiter-
                        #machen wuerde die Zuordnung zwischen OCR-Ausgabe und
                        #Hexcodes verschieben und die restliche Code-Tabelle
                        #unbrauchbar machen. Deshalb hier abbrechen -- was
                        #bisher erkannt wurde, bleibt gueltig.
                        print "FEHLER: Zeile " startline " von " utfcodes " laesst sich nicht rendern - breche die Zeichenerkennung fuer Font " fn " ab."
                        break
                    }

                    #Now run COR code
#		 print "OCR Textfile:",ocrfile
                    COMMAND=OCR " " QUOTE image QUOTE " " QUOTE ocrrootpageN QUOTE OCROPT
                    COMMAND | getline status; close(COMMAND)

                    # correct for some common mistakes and append output pages to a single textfile
                    COMMAND=AWK " -f correct.awk " QUOTE ocrfilepageN QUOTE APPEND QUOTE ocrfile QUOTE
                    system(COMMAND)

                    startline=endline+1
                }
		
                #Now create a translation file, whereby a hexcode is followed by
                #the respective ASCII code The ASCII codes is a list, if the
                #character was recognized mutliple times. The majority wins and is
                #printed as the first character in the line
                #Old translation tables are being reused to increase statistics
            
                print "Code table:",codetable
#		 print "Hexcode file:",hexcodes
#		 print "Comparing OCR output and text intput - assigning characters to HEXCODES"
                COMMAND=AWK " -v codetablefile=" quote(codetable) " -v hexcodefile=" quote(hexcodesmult) " -f decode.awk " QUOTE ocrfile QUOTE PIPE QUOTE codetable DOT "tmp" QUOTE 
                COMMAND | getline status; close(COMMAND)
	
                COMMAND=MOVE " " QUOTE codetable DOT "tmp" QUOTE " " QUOTE codetable QUOTE 
                COMMAND | getline status; close(COMMAND)
            
#		 print "........................................................................"
                print "Defuscating",spielplanfile,"for font",fn
                COMMAND=AWK " -f defuscate.awk -v codetablefile=" quote(codetable) " -v fontnumber=" fn " " QUOTE spielplanfile QUOTE PIPE QUOTE spielplanfiletmp QUOTE 
                COMMAND | getline status; close(COMMAND)
	
                COMMAND=MOVE " " QUOTE spielplanfiletmp QUOTE " " QUOTE spielplanfile QUOTE 
                COMMAND | getline status; close(COMMAND)
	
            }

            decodeerror=0
            for (stylei=1;stylei<=nstyle;stylei++) {
                style0=styles[stylei]
                if (!csvfile) outfile="spielplan-" Verein "-" style0 DOT OEXT[style0]
                else if (urli<=ncsv) outfile=csvfiles[urli] DOT OEXT[style0]
                else outfile=csvfiles[ncsv] DOT OEXT[style0]
                outfile=outdir DIRSEP outfile
                print " "
                #print "Creating output file", outfile
                
                COMMAND=AWK " -f fussball2csv.awk -v csvfile=" quote(outfile DOT "utf8") " -v style=" style0 " -v OS=" OS " -v NurHeimspiele=" NurHeimspiele " -v NurAuswaertsspiele=" NurAuswaertsspiele " -v Prefix=" QUOTE Prefix QUOTE " -v SequenceNR=" SequenceNR " -v ignoriereAbgesagt=" ignoriereAbgesagt " " QUOTE spielplanfile QUOTE
                syserror=system(COMMAND)
                if (syserror>0) decodeerror=1

                #Convert text from UTF8 to system format (easier for Umlaute)

                COMMAND=PERL " iconv.perl " quote(outfile DOT "utf8") " " quote(outfile)
                COMMAND | getline status; close(COMMAND)

                DELETEFILE(outfile DOT "utf8")

            } #end loop over styles
        } # end while loop over decodeerrors
    } # end loop over url
    
	
#    n=match(csvfile,"[.][A-Za-z0-9]+")
#    cancelcsvfile=substr(csvfile,1,n-1) "-cancel" substr(csvfile,n)
	
#    COMMAND=AWK " -f cancel.awk " QUOTE spielplanfile QUOTE PIPE QUOTE cancelcsvfile QUOTE 
#    system(COMMAND)
#    print "Created " cancelcsvfile
}

function quote(filename){
    returnfilename=QUOTE filename QUOTE
    if (OSFAMILY=="WIN") {
	gsub("[\\\\]","\\\\",returnfilename)
    }
#    print "Returnfilename=" returnfilename
    return returnfilename
}

function TESTMAKEDIR(dir) {
#    print "Testing if directory",dir,"exists."
    if (OSFAMILY=="MAC") {
	COMMAND="if [ ! -d " dir " ]; then  mkdir " dir "; echo \"Erstelle directory " dir "\"; fi"
    }
    else if (OSFAMILY="WIN") {
	COMMAND="IF NOT EXIST " QUOTE dir QUOTE " (MKDIR " QUOTE dir QUOTE " && echo Erstelle directory " dir " )"
    }
    else return
    COMMAND | getline status; close(COMMAND)
    if (status) print status
    status=""
}

#LOKALER PATCH (fussballcal): Wird gebraucht, um zu erkennen, ob ImageMagick
#ein Bild tatsaechlich erzeugt hat. Der Aufruf oben liefert seinen Exit-Code
#nicht zurueck ("COMMAND | getline" liest nur die Ausgabe), Fehler blieben
#deshalb bisher unbemerkt.
function FILEEXISTS(file) {
    if (OSFAMILY!="MAC") return 1
    COMMAND="if [ -s " QUOTE file QUOTE " ]; then echo 1; else echo 0; fi"
    COMMAND | getline fileexistsresult; close(COMMAND)
    return (fileexistsresult+0)
}

function DELETEFILE(file) {
#    print "Testing if file",file,"exists."
    if (OSFAMILY=="MAC") {
        COMMAND="if [ -f " file " ]; then  rm -f " file "; echo \"Deleting old file " file "\"; fi"
    }
    else if (OSFAMILY="WIN") {
        COMMAND="IF EXIST " QUOTE file QUOTE " (DEL /Q " QUOTE file QUOTE " && echo Deleting old file " file " )"
    }
    else return
    
    COMMAND | getline status; close(COMMAND)
    if (status) print status
    status=""
}

END{
    print "Ich bin dann mal fertig ...!"
    exit decodeerror
}

#type "C:\Users\Heino Falcke\SpielplanOffline\tmp\word-5770.txt" | convert -background none -fill black -font "C:\Users\Heino Falcke\SpielplanOffline\Fonts\font-5770.ttf" -pointsize 40 label:@- "image-5770.png"
#gawk -f runscript.awk -v ROOTDIR="C:\\Users\\Heino Falcke" -v url="http://www.fussball.de/mannschaft/bw-koenigsdorf-tus-bw-koenigsdorf-1900-ev-mittelrhein/-/saison/1516/team-id/016J70KIOO000000VV0AG811VSBH97M6#!/section/stage" -v StartDatum=2015-12-31 -v EndDatum=2016-06-30 -v OS=WIN64 runscript.awk
#http://vietocr.sourceforge.net/training.html
