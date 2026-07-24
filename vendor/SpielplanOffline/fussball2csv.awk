#Creates a .csv file for import of a soccer match schedule (Spielplan) into Google calendar or Excel from fussball.de
#License: Thanksware - free for non-commercial use, drop a note if you use it
#Version: 2.9
#Date: July 2015, update August 2017, minor update Jan 2018, 17 March 2018, August 2019, July 2021
#Author: Heino Falcke, h.falcke@astro.ru.nl
#(Mit Dank auch an G.Faber fuer kleine Erweiterungen)
#
#Reuses code from Version 1.0 of convert_csv_to_ics_v1.sh / 31.08.2010 / John L.
#
# Parameters:
# -v csvfile=Dateiname - Name der Datei mit dem Output im csv Format
# -v style=style       - Output-Style: ICS (Calendar file),ICSCSV,CALENDAR,TEXT,EXCEL (Komma-Separator),EXCEL2 (Semikolon)   
# -v Prefix="Text"     - Ein Schlüsselwort/Prefix, dass man vor jedes Spiel setzen kann (z.B. "Fussball", wenn man Kalender mit mehreren Sportarten hat)
# -v SequenceNR
# -v NurHeimspiele=1   - Gebe nur Heimspiele aus
# -v NurAuswaertsspiele=1  - Gebe nur Auswärtsspiele aus
#
# Beispiel:
# awk -f fussball2csv.awk -v csvfile=test.csv ~/Desktop/spielplan.html
# /opt/local/bin/gawk -f fussball2csv.awk -v csvfile=x.ics -v style=ICS -v Prefix="" -v SequenceNR=0 ~/SpielplanOffline/tmp/spielplan.html

BEGIN{

    #Das ist nicht gut, sollte von außen gesetzt werden

    if (!SequenceNR) SequenceNR=0
    
    True=1
    False=0
    verbose=True
    error=False
    totalerror=False
    dateset=False; timeset=False
    Ort="Spielort unbekannt"
    
    Dauer["A-Junioren"]=105
    Dauer["B-Junioren"]=95
    Dauer["C-Junioren"]=85
    Dauer["D-Junioren"]=75
    Dauer["E-Junioren"]=65
    Dauer["F-Junioren"]=55
    Dauer["G-Junioren"]=55
    Dauer["Bambini"]=50
    Dauer["A-Juniorinnen"]=105
    Dauer["B-Juniorinnen"]=95
    Dauer["C-Juniorinnen"]=85
    Dauer["D-Juniorinnen"]=75
    Dauer["E-Juniorinnen"]=65
    Dauer["F-Juniorinnen"]=55
    Dauer["G-Juniorinnen"]=55
    Dauer["Altsenioren"]=75
    Dauer["Altherren"]=75
    Dauer["Alte Herren"]=75
    Dauer["Herren"]=105
    Dauer["Frauen"]=105

    Spieldauer = Dauer["Herren"]
    
    FS=" *, *| *< *| *> *| *= *| *[|] *"

    # Prefix ist ein String, wenn es nicht gesetzt ist
    if (!Prefix) Prefix = ""
    else Prefix = Prefix " "

    if (!style) style="CALENDAR"
    if (!filetype) filetype="calendar"
    
    heim=1
    auswaerts=1
    nspiel=0
    heimmanschaft=True
    ignore=False
    firstheadline=True

    if (style == "ICS") {
    # HEADER / FOOTER FOR ICS-FILE
        HEADER="BEGIN:VCALENDAR\nMETHOD:PUBLISH\nVERSION:2.0\nPRODID:http://www.astro.ru.nl/~falcke/SpielplanOffline/\nX-WR-TIMEZONE:Europe/Berlin\nCALSCALE:GREGORIAN\nBEGIN:VTIMEZONE\nTZID:Europe/Berlin\nBEGIN:DAYLIGHT\nTZOFFSETFROM:+0100\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\nDTSTART:19810329T020000\nTZNAME:GMT+02:00\nTZOFFSETTO:+0200\nEND:DAYLIGHT\nBEGIN:STANDARD\nTZOFFSETFROM:+0200\nRRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\nDTSTART:19961027T030000\nTZNAME:GMT+01:00\nTZOFFSETTO:+0100\nEND:STANDARD\nEND:VTIMEZONE"
        FOOTER="END:VCALENDAR"

# SOME SETTINGS
        BEGINE="BEGIN:VEVENT"
        DTSTART1="DTSTART;"
        DTEND1="DTEND;"
        TRANSP="TRANSP:TRANSPARENT"
        SUMMARY="SUMMARY:"
        LOCATION1="LOCATION:"
        BEGINA="BEGIN:VALARM"
        SEQUENCE1="SEQUENCE:"
        SEQUENCE2=SequenceNR
        TRIGGER1="TRIGGER:-PT"
        REMINDER="00M" # i.e. zero minutes before or "01H" - 1 hour before
        SOUND="ATTACH;VALUE=URI:Ping"
        ACTION="ACTION:AUDIO"
        ENDVA="END:VALARM"
        ENDVE="END:VEVENT"

        DTSTART2="TZID=Europe/Berlin:"	
		DTEND2="TZID=Europe/Berlin:"			
    }
    if (style == "CALENDAR") print "Subject,Start Date,Start Time,End Date,End Time,All Day Event,Description,Location,Private" > csvfile
    else if (style == "ICSCSV") print "Start Date,Subject,Start Time,End Time,Location,Reminder,All Day Event" > csvfile
    else if (style == "ICS") print HEADER > csvfile
    else if (style == "EXCEL") print "Nr,Spielnunmmer,Datum,Heim,Gast,Zeit,EndZeit,Ort,Ergebnis,ToreHeim,ToreAusw,Wettbewerb,Gebiet,Mannschaftsart,SpielID,Wo,SpielURL" > csvfile
    else if (style == "EXCEL2") print "Nr;Spielnummer;Datum;Heim;Gast;Zeit;EndZeit;Ort;Ergebnis;ToreHeim;ToreAusw;Wettbewerb;Gebiet;Mannschaftsart;SpielID;Wo;SpielURL" > csvfile
    else if (style == "TEXT") print "" > csvfile
    else print "ERROR: Style " style " ist unbekannt!"

    if (verbose) print "------------------------------------------------------------------------"
    if (verbose) print "Ausgabeformat :",style
    if (verbose) print "Prefix        :",Prefix
    if (verbose) print "SequenceNR    :",SequenceNR
    if (verbose) print "Output-Datei  : " csvfile
    if (ignoriereAbgesagt) ausgabeabgesagt=", abgesagte Spiele werden ignoriert"
    else ausgabeabgesagt=", abgesagte Spiele werden mit aufgelistet"
    if (verbose) {
        if (NurHeimspiele) print "Ausgabe       : Nur Heimspiele" ausgabeabgesagt
        else if (NurAuswaertsspiele) print "Ausgabe       : Nur Auswärtsspiele" ausgabeabgesagt
        else print "Ausgabe       : Heim- und Auswärtsspiele" ausgabeabgesagt
    }
}

function web2txt(txt) {
    x=txt
    gsub("\\&nbsp;"," ",x)
    gsub("\0342\0200\0221","*-*")
    return x
}

function compactifyclubname(Name){
    Namekompakt=Name
    gsub("&#[0-9]+;","",Namekompakt) # Sonderzeichen
    sub("\\<AH\\>","",Namekompakt) # Alte Herren
    sub("\\<[A-Za-z]\\>","",Namekompakt) # Ein Buchstabe
    sub("\\<[0-9]+[.]*\\>","",Namekompakt) # Zahlenfolgen
    sub("\\<[.]*[e][.]*[Vv]\\>","",Namekompakt)  #e.V.
    sub("\\<[IV]+[.]*\\>","",Namekompakt)  # II, III
    sub("\\<[oO][.][wW][.]\\>","",Namekompakt) # ohne Wertung
    sub("\\<[(]*11-*er[)]\\>","",Namekompakt) #11er
    sub("\\<[(]*9-*er[)]\\>","",Namekompakt) #9er
    sub("\\<[uU][0-9]+\\>","",Namekompakt) # U19,U11,U9,...
    gsub("[^A-Za-z0-9 ]","",Namekompakt) #Dash,hyphen, Sonderzeichen
    gsub("  "," ",Namekompakt) #Double space
    Namekompakt=tolower(Namekompakt)
    lenary=split(Namekompakt,array," ")
    asort(array)
    NamekompaktSorted=""
    for (i=1;i<=lenary;i++) {
        NamekompaktSorted=NamekompaktSorted array[i]
    }
    return NamekompaktSorted
}

/^edGebietName/ {gsub("[';]",""); Gebiet=$2; print "Gebiet        : " Gebiet
    print "------------------------------------------------------------------------"
}

/<title>/{
    Titelmannschaft=$3
    print "Team          : " Titelmannschaft
    Titelmannschaftkompakt=compactifyclubname(Titelmannschaft)
    if (Titelmannschaft=="FUSSBALL.DE") {noHeimAusw=True}
}

/column-score/{
    getline
    if (match($0,"score-left..[0-9]")) scoreleft=substr($0,RSTART+12,1)
    else scoreleft=""
    if (match($0,"score-right..[0-9]")) scoreright=substr($0,RSTART+13,1)
    else scoreright=""
    score=scoreleft ":" scoreright;
    if (score==":") {scoreformatted=""; score=""}
    else scoreformatted=" (" score ") "
}

#Just look for date/time combination 
/[0-9][0-9][.,][0-9][0-9][.,][0-9][0-9][0-9][0-9] *[-_]+ *[0-9][0-9]:[0-9][0-9]/{
#    gsub(" ","")
    if (match($0,"[0-9][0-9][.,][0-9][0-9][.,][0-9]+")) {
        split(substr($0,RSTART,RLENGTH),datearray,"[,. ]+")
        Tag=datearray[1]
        Monat=datearray[2]
        Jahr=datearray[3]
        dateset=True
        if (Tag > 31 || Tag <= 0) {error=True; dateset=False; errordescription=errordescription " " "Tag falsch:" Tag}
        if (Monat > 12 || Monat <= 0) {error=True; dateset=False; errordescription=errordescription " " "Monat falsch:" Monat}
        if (Jahr > 2100 || Jahr <= 0) {error=True; dateset=False; errordescription=errordescription " " "Jahr falsch:" Jahr}
    } else if (!dateset) {error=True; errordescription=errordescription " " "Datumsformat falsch: "$0}
    if (match($0,"[0-9][0-9]:[0-9][0-9]")) {
        split(substr($0,RSTART,RLENGTH),datearray,"[:]")
        Stunde=datearray[1]
        Minuten=datearray[2]
        Zeit = Stunde ":" Minuten
        timeset=True
        if (Stunde > 23 || Stunde < 0) {error=True; timeset=False; errordescription=errordescription " " "Stunde falsch:" Stunde}
        if (Minuten > 59 || Minuten < 0) {error=True; timeset=False; errordescription=errordescription " " "Minuten falsch:" Minuten}
    } else if (!timeset) {error=True; errordescription=errordescription " " "Zeitformat falsch: " $0}
#    print "1]",dateset,timeset,Tag "-" Monat "-" Jahr,Stunde ":" Minuten, $0
}

#If the date/time wasn't found in the headline ...
/column-date/ {
#    gsub(" ","")
    if (!dateset) {
        if (match($0,"[0-9][0-9][.,][0-9][0-9][.,][0-9]+")) {
            split(substr($0,RSTART,RLENGTH),datearray,"[,. ]+")
            Tag=datearray[1]
            Monat=datearray[2]
            Jahr=datearray[3]
            dateset=True
            if (Tag > 31 || Tag <= 0) {error=True; dateset=False; errordescription=errordescription " " "Tag(2) falsch:" Tag}
            if (Monat > 12 || Monat <= 0) {error=True; dateset=False; errordescription=errordescription " " "Monat(2) falsch:" Monat}
            if (Jahr > 2100 || Jahr <= 0) {error=True; dateset=False; errordescription=errordescription " " "Jahr(2) falsch:" Jahr}
        } #else if (!dateset) {error=True; errordescription=errordescription " " "Datumsformat(2) falsch: "$0}
    }
    if (!timeset) {
        if (match($0,"[0-9][0-9]:[0-9][0-9]")) {
            split(substr($0,RSTART,RLENGTH),datearray,"[:]")
            Stunde=datearray[1]
            Minuten=datearray[2]
            Zeit = Stunde ":" Minuten
            timeset=True
            if (Stunde > 23 || Stunde < 0) {error=True; timeset=False; errordescription=errordescription " " "Stunde(2) falsch:" Stunde}
            if (Minuten > 59 || Minuten < 0) {error=True; timeset=False; errordescription=errordescription " " "Minuten(2) falsch:" Minuten}
        } #else if (!timeset) {error=True; errordescription=errordescription " " "Zeitformat(2) falsch: " $0}
    }
    if (timeset) {
        if (dateset) {
            lastTag=Tag
            lastMonat=Monat
            lastJahr=Jahr
        } else {
            dateset=True
            Tag=lastTag
            Monat=lastMonat
            Jahr=lastJahr
        }
       }
#    print "2]",dateset,timeset, Tag "-" Monat "-" Jahr,Stunde ":" Minuten, $0
}

#What type of Match is this?
/column-team/ {getline
    Mannschaftsart=$3
    Wettbewerb=$4
    if (Mannschaftsart in Dauer) Spieldauer=Dauer[Mannschaftsart]
    else Spieldauer=105
}


/[<]td colspan=["]2["][>]/ {getline;
    SpielType=$3;
    Spiel=$4;
    if (Spiel) {
        ID=substr(Spiel,1,6);
        Spiel=substr(Spiel,7,3)
    }
}

#Verlegtes Spiel - Referenz zu neuem Datum
/class *= *.info-text.[>].*[0-9][0-9].[0-9][0-9].[0-9][0-9]+ /{ignore=True} # verlegt
/[Ss][Pp][Ii][Ee][Ll][Ff][Rr][Ee][Ii]/ {ignore=True}
/[Aa][Bb][Gg][Ee][Ss][Aa][Gg][Tt]/ {abgesagt=True; if (ignoriereAbgesagt) ignore=True}
/class=.info-text.[>]Abse[.]/{abgesagt=True; if (ignoriereAbgesagt) ignore=True}
/class=.info-text.[>]Absetzung/{abgesagt=True; if (ignoriereAbgesagt) ignore=True}
/class=.info-text.[>]ABSETZUNG/{abgesagt=True; if (ignoriereAbgesagt) ignore=True}
/class=.info-text.[>][Ss]pielfrei/{spielfrei=True; ignore=True}

#<div class="match-teams"><span class="team-home">Viktoria Gruhlwerk</span><span class="colon"> - </span><span class="team-away">SpVg Frechen 20 2</span></div>

#Get the Name of a team
 /class *= *.club-name/{
     getline
     gsub("^[\t ]*","")
     gsub("[\t ]*$","")
     ClubName=$0; #$4
     gsub("&#[0-9]+;","",ClubName) # Sonderzeichen
     if (heimmanschaft) {Heim=web2txt(ClubName); heimmanschaft=0}
     else {Gast=web2txt(ClubName); heimmanschaft=1}
 }


#Get ID of match from URL to match
/www.fussball.de\/spiel\// {
     if (match($0,"/-/spiel/[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]+\"")) {
        SpielID=substr($0,RSTART+9,RLENGTH-10)
     }
}

/Spielst.+tte:/ {
    sub(".*Spielst.+tte:","");
    sub("</div>$","")
    gsub(" [|]",",")
    Ort=$0
}

#This separates matches
#	<tr class="odd row-competition hidden-small">
/tr +class *= *.row-headline/{
    heimmanschaft=True
    if (firstheadline) firstheadline=False
    else endofrecord=True
}
/\/tbody/{endofrecord=True}

(endofrecord) {
    Heimkompakt=compactifyclubname(Heim)
    Gastkompakt=compactifyclubname(Gast)
        
    isheim=index(Heimkompakt,Titelmannschaftkompakt) + index(Titelmannschaftkompakt,Heimkompakt)
    isausw=index(Gastkompakt,Titelmannschaftkompakt) + index(Titelmannschaftkompakt,Gastkompakt)
    HeimAusw="Unbekannt"
    if (isausw) {
        HeimAusw="Auswärts"
        if (NurHeimspiele) ignore=True
    }        
    if (isheim) {
        HeimAusw="Heimspiel";
        if (NurAuswaertsspiele) ignore=True
    }
        
    if (ignore) {
        ignore=False
    } else {

        if (!timeset) {error=True; errordescription=errordescription " " "Keine Zeit gefunden"}
        if (!dateset) {error=True; errordescription=errordescription " " "Kein Datum gefunden"}
        
        nspiel+=1
        # Try to determine who the home team is
        #Take out all kinds of extensions that are commonly added to a team or club name
    
        #Website of the match 
        SpielURL="http://www.fussball.de/spiel/-/spiel/" SpielID

        if (length(Jahr)==2) JahrNNNN=2000+Jahr
        else JahrNNNN=Jahr
        
        EndZeitInMinuten = Stunde*60 + Minuten + Spieldauer
        EndStunde = int(EndZeitInMinuten/60)
        EndMinuten = EndZeitInMinuten - (EndStunde*60)
        EndZeit = EndStunde ":" EndMinuten

        if (abgesagt) ABGESAGTTXT="ABGESAGT! "
        else ABGESAGTTXT=""

        if (error) {
            errortext="[FEHLER?] "
            totalerror=True # There is at least one error in the dates or times
        } else errortext=""

        HeimAuswBrackets=" [" HeimAusw "]"
        if (noHeimAusw) HeimAuswBrackets=""
    
        print nspiel "\t" Prefix errortext ABGESAGTTXT Tag "." Monat "." JahrNNNN "\t" Zeit "\t" Heim " - " Gast scoreformatted "\t\t (" Ort ")" HeimAuswBrackets
        if (error) print errordescription
        
        if (style == "CALENDAR") print Prefix errortext ABGESAGTTXT Heim " - " Gast scoreformatted " (" SpielType  HeimAuswBrackets " - " nspiel ". Spiel - Nr. " Spiel ")" "," Tag "/" Monat "/" JahrNNNN "," Zeit ":00,"Tag "/"  Monat "/" JahrNNNN "," EndStunde ":" EndMinuten ":00,False,\"" Wettbewerb " (" Gebiet "/" Mannschaftsart  ")" " [ID: " ID "-" Spiel "]"  " importiert mit SpielplanOffline " processdate "\"" ",\"" Ort "\",False" >> csvfile
        else if (style == "ICS") {
            DTSTARTSUM=DTSTART1 DTSTART2 sprintf("%4.4i",JahrNNNN)  sprintf("%2.2i",Monat) sprintf("%2.2i",Tag) "T" sprintf("%2.2i",Stunde) sprintf("%2.2i",Minuten) "00"
            DTENDSUM=DTEND1 DTEND2 sprintf("%4.4i",JahrNNNN)  sprintf("%2.2i",Monat) sprintf("%2.2i",Tag) "T" sprintf("%2.2i",EndStunde) sprintf("%2.2i",EndMinuten) "00"
        print " " >>csvfile			
		print  BEGINE >>csvfile
        print "UID:" SpielID "@SpielplanOffline" >>csvfile
		print  DTSTARTSUM >>csvfile			
		print  DTENDSUM >>csvfile			
		print  TRANSP >>csvfile			
		print  SUMMARY  Prefix errortext ABGESAGTTXT Heim " - " Gast scoreformatted " (" SpielType ",  " Mannschaftsart  HeimAuswBrackets ")" " [ID: " ID "-" Spiel "]" >>csvfile
        
        print "DESCRIPTION:"  Wettbewerb " " Gebiet "/" Mannschaftsart ", "  nspiel ". Spiel - Nr. " Spiel ", importiert mit SpielplanOffline(HF) " processdate  >>csvfile
        location=Ort; gsub(",","\\,",location)
		print  LOCATION1 location >>csvfile
        print  "URL;VALUE=URI:" SpielURL >>csvfile
		print  SEQUENCE1 SEQUENCE2 >>csvfile			
#		print  BEGINA >>csvfile			
#		print  TRIGGER1 REMINDER >>csvfile			
#		print  SOUND >>csvfile			
#		print  ACTION >>csvfile			
#		print  ENDVA >>csvfile			
		print  ENDVE >>csvfile
        }
        else if (style == "ICSCSV") print Tag "/" Monat "/" JahrNNNN ";" Prefix errortext ABGESAGTTXT Heim " - " Gast scoreformatted " (" SpielType HeimAuswBrackets " - " nspiel ". Spiel - Nr. " Spiel ")" Wettbewerb " (" Gebiet "/" Mannschaftsart  ")" " [ID: " ID "-" Spiel "]" ";" Zeit ":00;" EndStunde ":" EndMinuten ":00;\"" Ort "\";0H;0" >> csvfile
        else if (style == "EXCEL") print nspiel "," Spiel "," Tag "." Monat "." JahrNNNN "," Prefix errortext ABGESAGTTXT  Heim "," Gast "," Zeit "," EndZeit "," "\"" Ort "\"" "," score "," scoreleft "," scoreright "," Wettbewerb ","  Gebiet "," Mannschaftsart  "," ID "-" Spiel "," HeimAusw "," SpielURL >> csvfile
        else if (style == "EXCEL2") print nspiel ";" Spiel ";" Tag "." Monat "." JahrNNNN ";" Prefix errortext ABGESAGTTXT  Heim ";" Gast ";" Zeit ";" EndZeit ";" "\"" Ort "\"" ";" score ";" scoreleft ";" scoreright ";" Wettbewerb ";"  Gebiet ";" Mannschaftsart  ";" ID "-" Spiel ";" HeimAusw ";" SpielURL >> csvfile
        else if (style == "TEXT") print nspiel "\t" Tag "." Monat "." JahrNNNN "\t" Zeit "\t" Prefix errortext ABGESAGTTXT  Heim " - " Gast scoreformatted "\t (" Ort ")" " " HeimAusw>> csvfile
    }
    Spieldauer = Dauer["Herren"]
    SpielID=""
    Heim=""
    Gast=""
    Tag=0; Monat=0; Jahr=0; Stunde=0; Minuten=0
    score=""; scoreformatted=""
    Ort="Spielort unbekannt"
    endofrecord=False
    error=False
    abgesagt=False
    dateset=False; timeset=False
    errordescription=""
}

END{
    if (style == "ICS") print "\n" FOOTER >>csvfile
    print "------------------------------------------------------------------------"
    if (totalerror) {
        print "FEHLER!!! Mindestens ein Datum stimmt nicht."
        exit 1
    } else exit 0
}
