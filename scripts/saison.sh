#!/bin/bash
#
# saison.sh — Saisonlogik, gemeinsam genutzt von update_all.sh und selftest.sh.
#
# Diese Datei wird gesourct und gibt selbst nichts aus. Sie enthält die
# Entscheidung, die man aus den Daten von fussball.de überhaupt treffen kann:
# ob für eine Mannschaft noch Spiele anstehen.
#
# Wichtig zum Verständnis der Grenzen: fussball.de liefert keinen Saisonstart
# und kein Saisonende. Geholt wird eine Druckansicht des Spielplans für ein
# angefragtes Datumsfenster — Felder sind Datum, Uhrzeit, Heim, Gast, Ort,
# Ergebnis, Wettbewerb, Spielnummer. Kein Spieltag, keine Spieltagszahl, keine
# Tabelle. Das einzige Signal für "Saison vorbei" ist die Abwesenheit von
# Spielen, und die ist nicht endgültig: nach dem letzten Ligaspieltag folgen
# Nachhol-, Relegations- und Pokalspiele, und verlegte Spiele wirft
# fussball2csv.awk ganz weg, bis sie mit neuem Datum wieder auftauchen.
#
# Deshalb behauptet hier kein Status "Saison vorbei" — nur "vermutlich
# beendet" und "keine weiteren Spiele zu erwarten".

# Wie weit das Saisonfenster über die nominelle Spielzeit (1.7. bis 30.6.)
# hinausreicht.
#
# Die Spielordnungen definieren das Spieljahr einheitlich als 1. Juli bis
# 30. Juni und erlauben den Sportinstanzen, darüber hinaus anzusetzen. Im
# Normalbetrieb passiert das aber nicht: Relegation, Entscheidungs- und
# Pokalendspiele liegen im Mai und Juni, und selbst der Nachholstau eines
# harten Winters wird bis zum Saisonende abgearbeitet. Ein Monat Luft reicht
# also — das entspricht auch der Vorgabe, die der Autor von SpielplanOffline
# selbst gewählt hatte (1.8. bis 31.7., runscript.awk:194).
#
# Der eine bekannte Gegenfall ist die Pandemie: der BFV hat die Saison 2019/20
# von der Bayernliga abwärts bis zum 30.6.2021 gestreckt, weil der Spielbetrieb
# erst ab September 2020 wieder möglich war. Das ist aus den Daten nicht
# erkennbar — nach der Unterbrechung klafft eine Lücke, das letzte sichtbare
# Spiel liegt weit vor dem Fensterende, und fenster_zu_eng() schlägt deshalb
# nicht an. Dafür gibt es SPO_SAISON_NACHLAUF: eine Variable, kein Patch.
#
# Gegen einen sehr weiten Nachlauf spricht die Überlappung — das Fenster reicht
# sonst tief in die Folgesaison, deren Pokalrunden schon in der zweiten
# Julihälfte beginnen.
#
# Der Nachlauf wird auf den nominellen Saisonbeginn der Folgesaison (1.7.)
# gerechnet und dann ein Tag abgezogen, damit jeder Wert auf einem Monatsende
# landet: 1 month -> 31.07., 2 months -> 31.08., 6 months -> 31.12.
SAISON_VORLAUF="${SPO_SAISON_VORLAUF:-1 month}"
SAISON_NACHLAUF="${SPO_SAISON_NACHLAUF:-1 month}"

# Ab wann "kein Spiel mehr in der Zukunft" als Saisonende gilt — gemeint ist
# der Abstand nach dem *letzten* Spiel, nicht eine Lücke im Ansetzungsplan.
SAISON_KARENZ_TAGE="${SPO_SAISON_KARENZ:-21}"

# Abstand vom Fensterende, ab dem das Fenster als möglicherweise zu eng gilt.
SAISON_RANDABSTAND_TAGE="${SPO_SAISON_RANDABSTAND:-14}"

# Wie lange nach Fensterbeginn eine leere Ausgabe noch als Vorsaison durchgeht
# (Staffeleinteilung steht dann oft noch nicht).
SAISON_VORSAISON_FRIST="${SPO_SAISON_VORSAISON_FRIST:-3 months}"

# Liest die Saison aus einer fussball.de-URL und leitet daraus das
# Abfragefenster ab. Setzt SAISON, SAISON_NOMINALENDE, FENSTER_START und
# FENSTER_ENDE; Rückgabe 1, wenn die URL keine Saison nennt.
#
# fussball.de führt die Saison als vierstellige Jahrespaarung im Pfad
# (".../saison/2526/..."). Es gibt auch eine Variante, in der an derselben
# Stelle eine 32-stellige interne ID steht — die ist hier bewusst nicht
# unterstützt, sie lässt sich nicht in Datumsgrenzen umrechnen. Ebenso
# ausgeschlossen ist der Jahrhundertwechsel ("9900"): "20" davor zu setzen
# ergäbe 2099/2000, und so alte Spielpläne hat fussball.de nicht.
saison_aus_url() {
    local url="$1" yy1 yy2

    SAISON=""; SAISON_NOMINALENDE=""; FENSTER_START=""; FENSTER_ENDE=""

    [[ "$url" =~ /saison/([0-9][0-9])([0-9][0-9])(/|$|\#) ]] || return 1
    yy1="${BASH_REMATCH[1]}"
    yy2="${BASH_REMATCH[2]}"

    # Eine Saison umfasst zwei aufeinanderfolgende Jahre. Alles andere ist
    # keine Saisonangabe, sondern ein Zufallstreffer im Pfad.
    (( 10#$yy2 == 10#$yy1 + 1 )) || return 1

    SAISON="$yy1$yy2"
    # Nominell 1.7. bis 30.6. — nur für Anzeige und für den spätesten Status,
    # NICHT als Filtergrenze.
    SAISON_NOMINALENDE="20$yy2-06-30"
    FENSTER_START="$(date -d "20$yy1-07-01 -$SAISON_VORLAUF" +%F)"
    FENSTER_ENDE="$(date -d "20$yy2-07-01 +$SAISON_NACHLAUF -1 day" +%F)"
    return 0
}

# Kennzahlen einer ICS-Datei. Setzt NEVENTS, LETZTES_SPIEL (YYYYMMDD, leer wenn
# keine Termine) und SPIELE_ZUKUNFT.
#
# Gefiltert wird auf "DTSTART;" mit Parameter – der Zeitzonenblock im Kopf
# enthält ebenfalls DTSTART-Zeilen, aber ohne Parameter ("DTSTART:19810329...").
ics_kennzahlen() {
    local f="$1" datumsliste heute="${2:-$(date +%Y%m%d)}"

    NEVENTS=$(grep -c '^BEGIN:VEVENT' "$f" || true)
    datumsliste=$(sed -n 's/^DTSTART;[^:]*:\([0-9]\{8\}\).*/\1/p' "$f" | sort)

    if [ -z "$datumsliste" ]; then
        LETZTES_SPIEL=""
        SPIELE_ZUKUNFT=0
        return 0
    fi

    LETZTES_SPIEL=$(printf '%s\n' "$datumsliste" | tail -1)
    SPIELE_ZUKUNFT=$(printf '%s\n' "$datumsliste" | awk -v heute="$heute" '$1 >= heute' | wc -l)
}

# Ordnet der Ausgabe einen Saisonstatus zu. Setzt STATUS auf einen von:
#
#   LAUFEND                     es stehen noch Spiele an
#   SAISONENDE_VERMUTLICH       Termine vorhanden, keiner mehr in der Zukunft,
#                               das letzte länger als die Karenz her
#   KEINE_SPIELE_MEHR_ERWARTET  zusätzlich ist das Saisonfenster abgelaufen
#   VORSAISON                   keine Termine, aber Saisonanfang – normal
#   LEER_UNERWARTET             keine Termine mitten in der Saison – verdächtig
#
# Erwartet NEVENTS/LETZTES_SPIEL/SPIELE_ZUKUNFT aus ics_kennzahlen() und
# FENSTER_START/FENSTER_ENDE aus saison_aus_url() (oder leer, dann entfallen
# die kalenderabhängigen Stufen). Kein Logging – das macht der Aufrufer.
saison_status() {
    local heute="${1:-$(date +%Y%m%d)}" karenzgrenze vorsaisongrenze fensterende=""

    [ -n "${FENSTER_ENDE:-}" ] && fensterende=$(date -d "$FENSTER_ENDE" +%Y%m%d)

    if [ "$NEVENTS" -gt 0 ] && [ "$SPIELE_ZUKUNFT" -gt 0 ]; then
        STATUS="LAUFEND"
        return 0
    fi

    if [ "$NEVENTS" -gt 0 ]; then
        # Termine vorhanden, aber keiner mehr in der Zukunft. Das ist das
        # belastbarere Kriterium, weil es ohne Kalenderannahmen funktioniert.
        karenzgrenze=$(date -d "$heute -$SAISON_KARENZ_TAGE days" +%Y%m%d)
        if (( 10#${LETZTES_SPIEL:-0} < 10#$karenzgrenze )); then
            if [ -n "$fensterende" ] && (( 10#$heute > 10#$fensterende )); then
                STATUS="KEINE_SPIELE_MEHR_ERWARTET"
            else
                STATUS="SAISONENDE_VERMUTLICH"
            fi
        else
            # Innerhalb der Karenz: kann auch schlicht Winterpause oder eine
            # Lücke im Ansetzungsplan sein.
            STATUS="LAUFEND"
        fi
        return 0
    fi

    # Gar keine Termine. Am Saisonanfang ist das normal – die Staffeleinteilung
    # steht dann noch nicht –, mitten in der Saison ist es verdächtig.
    if [ -n "${FENSTER_START:-}" ]; then
        vorsaisongrenze=$(date -d "$FENSTER_START +$SAISON_VORSAISON_FRIST" +%Y%m%d)
        if (( 10#$heute < 10#$vorsaisongrenze )); then
            STATUS="VORSAISON"
            return 0
        fi
        if [ -n "$fensterende" ] && (( 10#$heute > 10#$fensterende )); then
            STATUS="KEINE_SPIELE_MEHR_ERWARTET"
            return 0
        fi
    fi

    STATUS="LEER_UNERWARTET"
}

# Prüft, ob das letzte gefundene Spiel am Rand des Abfragefensters klebt.
#
# Dann hat das Fenster vermutlich abgeschnitten, und "keine Spiele mehr" wäre
# ein Artefakt der Abfrage statt eine Aussage über die Saison. Rückgabe 0 =
# Fenster verdächtig eng.
fenster_zu_eng() {
    local randgrenze

    [ -n "${LETZTES_SPIEL:-}" ] && [ -n "${FENSTER_ENDE:-}" ] || return 1
    randgrenze=$(date -d "$FENSTER_ENDE -$SAISON_RANDABSTAND_TAGE days" +%Y%m%d)
    (( 10#$LETZTES_SPIEL > 10#$randgrenze ))
}

# Hängt einen Hinweis-Termin an den Kalender.
#
# Der Kalender selbst ist der einzige Kanal, der bestehende Abos erreicht: die
# Abonnenten stehen nirgends, und einen Hinweis auf der Website sehen nur die,
# die sie noch einmal aufrufen. Deshalb steht am Ende der Saison ein
# Ganztags-Termin im Spielplan.
#
# Nichts davon muss aufgeräumt werden, wenn der Status zurück auf LAUFEND
# springt: die ICS wird bei jedem Lauf neu erzeugt, der Hinweis kommt dann
# einfach nicht mehr dazu. Die feste UID verhindert, dass Kalender-Apps ihn
# doppelt anzeigen, falls sie zwei Fassungen sehen.
#
# Erwartet LETZTES_SPIEL und SAISON. SUMMARY und DESCRIPTION stehen bewusst in
# je einer langen Zeile statt nach RFC 5545 umgebrochen ("folding"): so macht es
# fussball2csv.awk für alle anderen Termine auch, und die Kalender-Apps kommen
# damit erwiesenermaßen zurecht. Ein falsch eingerückter Umbruch fiele dagegen
# als verstümmelter Text auf.
ergaenze_saisonhinweis() {
    local f="$1" slug="$2" ab bis saisontext

    # Tag nach dem letzten Spiel; DTEND ist bei Ganztagsterminen exklusiv.
    ab=$(date -d "$LETZTES_SPIEL +1 day" +%Y%m%d)
    bis=$(date -d "$LETZTES_SPIEL +2 days" +%Y%m%d)

    if [ -n "${SAISON:-}" ]; then
        saisontext="Saison ${SAISON:0:2}/${SAISON:2:2}"
    else
        saisontext="Die Saison"
    fi

    {
        grep -v '^END:VCALENDAR$' "$f"
        cat <<EOF

BEGIN:VEVENT
UID:saisonende-$slug-${SAISON:-x}@fussballcal
DTSTAMP:$(date -u +%Y%m%dT%H%M%SZ)
DTSTART;VALUE=DATE:$ab
DTEND;VALUE=DATE:$bis
TRANSP:TRANSPARENT
SUMMARY:$saisontext ist beendet – neuen Kalender abonnieren
DESCRIPTION:Für diese Mannschaft stehen keine weiteren Spiele an. fussball.de vergibt pro Saison eigene Links\, dieses Abo läuft also nicht von selbst mit der neuen Saison weiter: den Kalender der neuen Saison gibt es auf der Übersichtsseite dieses Dienstes\, das alte Abo kann danach in der Kalender-App entfernt werden.\n\nWerden doch noch Nachhol- oder Pokalspiele angesetzt\, verschwindet dieser Hinweis beim nächsten Abgleich von selbst.
SEQUENCE:0
END:VEVENT
END:VCALENDAR
EOF
    } >"$f.hinweis"

    mv "$f.hinweis" "$f"
}
