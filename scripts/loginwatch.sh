#!/bin/bash
#
# loginwatch.sh — meldet gehäufte Fehlversuche am Eintrage-Formular.
#
# Basic Auth kennt keine Sperre nach n Fehlversuchen; die Bremse davor ist das
# Rate-Limit im vhost (limit_req zone=fussballcal_login). Beides steht aber nur
# im nginx-Log — es sieht sie also niemand. Dieses Skript liest das Log aus,
# fasst zusammen und gibt bei Auffälligkeiten einen Bericht auf stdout aus.
#
# Gemailt wird der Bericht nicht von hier, sondern von cron: Was ein Cron-Job
# ausgibt, geht an root (bzw. an MAILTO). Deshalb schweigt das Skript im
# Normalfall vollständig — keine Ausgabe, keine Mail. Es braucht damit weder
# einen MTA noch ein `mail`-Binary und hat keine Meinung dazu, wie Mail auf
# diesem Server zugestellt wird.
#
# Ausgewertet werden zwei Zeilenarten aus dem nginx-error.log:
#
#   ... limiting requests, excess: 5.700 by zone "fussballcal_login",
#       client: 203.0.113.7, ...            -> Block (429), zu schnell geklopft
#   ... user "admin": password mismatch, client: 203.0.113.7, ...
#   ... user "x" was not found in "...", client: 203.0.113.7, ...
#                                           -> Fehllogin am Formular
#
# Die zweite Art ist die wichtigere: Wer langsamer als eine Anfrage pro Sekunde
# rät, löst das Rate-Limit nie aus und käme in einer reinen 429-Auswertung gar
# nicht vor. Nicht gezählt wird dagegen "no user/password was provided for
# basic authentication" — diese Zeile entsteht bei jedem ersten Seitenaufruf,
# bevor der Browser überhaupt nach Zugangsdaten fragt. Sie zu zählen hieße,
# jeden regulären Login als Angriff zu melden.
#
# Gegen Mailflut wirken drei Dinge (Werte siehe unten, alle per Umgebung
# überschreibbar):
#
#   Schwellen   Gemeldet wird erst ab N Blocks bzw. M Fehllogins einer Adresse.
#               Der genervte Admin mit dem Reload-Finger (burst=5) bleibt damit
#               unter dem Radar.
#   Ruhezeit    Nach einem Bericht ist Sendepause. Was in dieser Zeit passiert,
#               geht nicht verloren, sondern wird weitergezählt und kommt im
#               nächsten Bericht mit.
#   Eskalation  Hält ein Angriff an, verdoppelt sich die Ruhezeit mit jedem
#               Bericht (bis maximal ein Tag). Aus tagelangem Klopfen werden so
#               eine Handvoll Mails statt hunderttausender.
#
# Angefasst wird ausschließlich die eigene Zustandsdatei unter
# $SPO_STATE_DIR. Das nginx-Log wird nur gelesen; an der Auslieferung der
# Kalender ändert dieses Skript nichts.
#
# Aufruf:
#   ./loginwatch.sh             # für cron: still, außer es gibt etwas zu melden
#   ./loginwatch.sh --dry-run   # ganzes Log auswerten und zeigen, ohne Zustand
#   ./loginwatch.sh --status    # aktuellen Zustand anzeigen
#
# Rückgabe: 0 = Lauf in Ordnung (auch wenn gemeldet wurde), >0 = Fehler.

set -euo pipefail

SKRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pfade der Installation, wie deploy.sh sie neben dieses Skript geschrieben hat
# (spo.env). Umgebungsvariablen gehen vor.
SPO_ENV="${SPO_ENV:-$SKRIPT_DIR/spo.env}"
if [ -r "$SPO_ENV" ]; then
    . "$SPO_ENV"
fi

# Das nginx-Fehlerlog. Debian schreibt es nach /var/log/nginx/error.log und
# rotiert es täglich; auf den Wechsel ist unten geachtet.
NGINX_LOG="${LOGINWATCH_LOG:-/var/log/nginx/error.log}"
STATE_DIR="${SPO_STATE_DIR:-/var/lib/fussballcal}"
STATE="${LOGINWATCH_STATE:-$STATE_DIR/loginwatch.state}"

# Name der Rate-Limit-Zone aus dem vhost und der geschützte Pfad. Beides muss
# zu nginx/fussballcal.conf passen, sonst findet die Auswertung nichts.
ZONE="${LOGINWATCH_ZONE:-fussballcal_login}"
PFAD="${LOGINWATCH_PATH:-/add_team.php}"

# Ab wann ist es meldenswert?
SCHWELLE_BLOCKS="${LOGINWATCH_BLOCKS:-20}"        # 429er einer Adresse
SCHWELLE_FEHLLOGIN="${LOGINWATCH_AUTHFAILS:-10}"  # falsche Passwörter einer Adresse
SCHWELLE_IPS="${LOGINWATCH_IPS:-3}"               # verschiedene Adressen gleichzeitig

RUHEZEIT="${LOGINWATCH_COOLDOWN:-3600}"           # Sendepause nach einem Bericht (s)
RUHEZEIT_MAX="${LOGINWATCH_COOLDOWN_MAX:-86400}"  # Obergrenze der Eskalation (s)
VERFALL="${LOGINWATCH_WINDOW:-86400}"             # so lange wird mitgezählt (s)

# Obergrenze für die Zahl gleichzeitig verfolgter Adressen. Ohne sie könnte ein
# verteilter Scan den Speicher des Auswerteprozesses (läuft als root) beliebig
# wachsen lassen. Was darüber hinausgeht, wird nur noch gezählt.
MAX_IPS="${LOGINWATCH_MAX_IPS:-5000}"

modus="cron"
for arg in "$@"; do
    case "$arg" in
        --dry-run) modus="dry-run" ;;
        --status)  modus="status" ;;
        -h|--help)
            sed -n '3,53p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unbekannte Option: $arg (siehe --help)" >&2
            exit 2 ;;
    esac
done

JETZT="$(date +%s)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TAB="$(printf '\t')"

# Ruhezeit für eine Eskalationsstufe: Stufe 0 und 1 = Grundwert, danach
# Verdopplung je Stufe, gedeckelt.
ruhezeit_fuer() {
    local stufe="$1" wert="$RUHEZEIT" i=1
    while [ "$i" -lt "$stufe" ] && [ "$wert" -lt "$RUHEZEIT_MAX" ]; do
        wert=$((wert * 2))
        i=$((i + 1))
    done
    [ "$wert" -le "$RUHEZEIT_MAX" ] || wert="$RUHEZEIT_MAX"
    echo "$wert"
}

# ------------------------------------------------------------------
# Zustand lesen
#
# Eine einzige Datei, damit sie in einem Rutsch geschrieben werden kann
# (Temp + mv): Ein abgebrochener Lauf hinterlässt so keinen halben Zustand.
#
#   pos <inode> <offset>   wie weit das Log gelesen ist
#   report <epoch> <stufe> wann zuletzt gemeldet wurde, und die wievielte Folge
#   ip <adresse> <blocks> <fehllogins> <erstmals> <zuletzt> <gesehen-epoch>
# ------------------------------------------------------------------
pos_inode=0
pos_offset=0
letzter_bericht=0
eskalation=0
: >"$TMP/acc"

if [ -r "$STATE" ]; then
    while IFS= read -r zeile; do
        case "$zeile" in
            'pos '*)    read -r _ pos_inode pos_offset _ <<<"$zeile " ;;
            'report '*) read -r _ letzter_bericht eskalation _ <<<"$zeile " ;;
            'ip '*)     printf '%s\n' "${zeile#ip }" >>"$TMP/acc" ;;
        esac
    done <"$STATE"
fi

# Bei beschädigtem oder unvollständigem Zustand lieber bei null anfangen als
# mit Müll rechnen — eine kaputte Zahl brächte unten die Arithmetik zu Fall.
for v in pos_inode pos_offset letzter_bericht eskalation; do
    case "${!v}" in
        ''|*[!0-9]*) printf -v "$v" '%s' 0 ;;
    esac
done

if [ "$modus" = "status" ]; then
    echo "fussballcal — loginwatch, aktueller Zustand"
    echo "  Zustandsdatei:  $STATE"
    echo "  nginx-Log:      $NGINX_LOG"
    if [ "$pos_inode" -eq 0 ]; then
        echo "  Leseposition:   noch nicht gesetzt (erster Lauf steht aus)"
    else
        echo "  Leseposition:   Inode $pos_inode, Byte $pos_offset"
    fi
    if [ "$letzter_bericht" -gt 0 ]; then
        echo "  Letzte Meldung: $(date -d "@$letzter_bericht" '+%F %T')" \
             "(Stufe $eskalation, Sendepause $(( $(ruhezeit_fuer "$eskalation") / 60 )) min)"
    else
        echo "  Letzte Meldung: noch keine"
    fi
    if [ -s "$TMP/acc" ]; then
        echo "  Seit der letzten Meldung mitgezählt:"
        awk -F'\t' '{ printf "    %-39s %6d Blocks  %6d Fehllogins  zuletzt %s\n", $1, $2, $3, $5 }' "$TMP/acc"
    else
        echo "  Seit der letzten Meldung mitgezählt: nichts"
    fi
    exit 0
fi

# Überlappende Läufe würden dieselben Zeilen zweimal zählen. Läuft schon einer,
# ist das kein Fehler — der nächste Cron-Takt kommt bestimmt.
if [ "$modus" != "dry-run" ]; then
    if ! install -d -m 750 "$(dirname "$STATE")" 2>/dev/null; then
        # Klare Ansage statt eines rohen Shell-Fehlers: Der Cron-Job gehört in
        # die crontab von root, sonst gibt es kein Leserecht auf das nginx-Log
        # und keinen Schreibzugriff auf den Zustand.
        echo "loginwatch: $(dirname "$STATE") lässt sich nicht anlegen." >&2
        echo "  Läuft der Job als root? (sudo crontab -e)" >&2
        exit 1
    fi
    exec 201>"$STATE.lock"
    flock -n 201 || exit 0
fi

# ------------------------------------------------------------------
# Neue Logzeilen holen
# ------------------------------------------------------------------
if [ ! -r "$NGINX_LOG" ]; then
    # Kein Grund für eine Mail: Entweder läuft hier kein nginx (dann gehört der
    # Cron-Job nicht auf diese Maschine), oder logrotate hat die Datei gerade
    # bewegt und nginx legt sie im nächsten Moment neu an. Wer nachsehen will,
    # nimmt --status.
    exit 0
fi

log_inode="$(stat -c %i "$NGINX_LOG")"
log_size="$(stat -c %s "$NGINX_LOG")"

: >"$TMP/neu"
erstlauf=0

if [ "$modus" = "dry-run" ]; then
    # Für die Sichtprüfung von Hand: das ganze Log, unabhängig von der
    # gespeicherten Position.
    [ ! -r "$NGINX_LOG.1" ] || cat "$NGINX_LOG.1" >>"$TMP/neu"
    cat "$NGINX_LOG" >>"$TMP/neu"
elif [ "$pos_inode" -eq 0 ]; then
    # Erster Lauf: nur die aktuelle Position merken und sonst nichts tun. Sonst
    # käme als Erstes ein Bericht über Monate alte Logzeilen — und zwar genau
    # einmal, was ihn maximal verwirrend macht.
    erstlauf=1
    pos_offset="$log_size"
elif [ "$log_inode" -ne "$pos_inode" ]; then
    # Rotiert. Der Rest der alten Datei liegt bei Debian als error.log.1 (noch
    # unkomprimiert, delaycompress). Ohne diesen Zweig fiele alles unter den
    # Tisch, was zwischen dem letzten Lauf und der Rotation geschrieben wurde.
    if [ -r "$NGINX_LOG.1" ] && [ "$(stat -c %i "$NGINX_LOG.1")" = "$pos_inode" ]; then
        tail -c "+$((pos_offset + 1))" "$NGINX_LOG.1" >>"$TMP/neu" || true
    fi
    cat "$NGINX_LOG" >>"$TMP/neu"
    pos_offset=0
elif [ "$pos_offset" -gt "$log_size" ]; then
    # Abgeschnitten (copytruncate o.ä.) — von vorne lesen.
    cat "$NGINX_LOG" >"$TMP/neu"
    pos_offset=0
else
    tail -c "+$((pos_offset + 1))" "$NGINX_LOG" >"$TMP/neu" || true
fi

# Genau so viele Bytes, wie tatsächlich gelesen wurden — nicht bis $log_size.
# nginx schreibt weiter, während dieses Skript läuft; die Differenz würde sonst
# beim nächsten Lauf ein zweites Mal gezählt.
neue_position=$((pos_offset + $(stat -c %s "$TMP/neu")))

# ------------------------------------------------------------------
# Auswerten: pro Adresse zusammenfassen
# Ausgabe (TSV): adresse  blocks  fehllogins  erstmals  zuletzt
# ------------------------------------------------------------------
: >"$TMP/spill"
awk -v zone="$ZONE" -v pfad="$PFAD" -v maxips="$MAX_IPS" -v spillfile="$TMP/spill" '
    {
        p = index($0, "client: ")
        if (p == 0) next
        rest = substr($0, p + 8)
        komma = index(rest, ",")
        ip = (komma > 0) ? substr(rest, 1, komma - 1) : rest
        if (ip == "") next

        if (index($0, "by zone \"" zone "\"") > 0) {
            typ = "block"
        } else if (index($0, pfad) > 0 &&
                   (index($0, "password mismatch") > 0 || index($0, "was not found in") > 0)) {
            typ = "auth"
        } else {
            next
        }

        if (!(ip in gesehen)) {
            if (n >= maxips) { spill++; next }
            n++
            gesehen[ip] = 1
            erstmals[ip] = substr($0, 1, 19)
        }
        zuletzt[ip] = substr($0, 1, 19)
        if (typ == "block") blocks[ip]++; else fehllogin[ip]++
    }
    END {
        for (ip in gesehen)
            printf "%s\t%d\t%d\t%s\t%s\n", ip, blocks[ip] + 0, fehllogin[ip] + 0, erstmals[ip], zuletzt[ip]
        if (spill > 0) printf "%d\n", spill > spillfile
    }
' "$TMP/neu" >"$TMP/frisch"

# ------------------------------------------------------------------
# Mit dem bisher Mitgezählten verrechnen; dabei verfallen alte Einträge.
# ------------------------------------------------------------------
# Der Vergleich läuft über FILENAME, nicht über das übliche FNR==NR: Ist die
# Zustandsdatei leer, wäre FNR==NR beim zweiten Eingabefile wahr, und die
# frischen Zahlen würden als alter Stand gelesen.
awk -F'\t' -v jetzt="$JETZT" -v verfall="$VERFALL" -v alt="$TMP/acc" '
    FILENAME == alt {
        if (jetzt - $6 <= verfall) {
            blocks[$1] = $2; fehllogin[$1] = $3
            erstmals[$1] = $4; zuletzt[$1] = $5; gesehen[$1] = $6
            reihe[++n] = $1
        }
        next
    }
    {
        if (!($1 in blocks)) { reihe[++n] = $1; erstmals[$1] = $4 }
        blocks[$1] += $2; fehllogin[$1] += $3
        zuletzt[$1] = $5; gesehen[$1] = jetzt
    }
    END {
        for (i = 1; i <= n; i++) {
            ip = reihe[i]
            printf "%s\t%d\t%d\t%s\t%s\t%d\n", \
                   ip, blocks[ip], fehllogin[ip], erstmals[ip], zuletzt[ip], gesehen[ip]
        }
    }
' "$TMP/acc" "$TMP/frisch" >"$TMP/acc_neu"

# ------------------------------------------------------------------
# Reicht es für eine Meldung?
# ------------------------------------------------------------------
ausloeser="$(awk -F'\t' -v sb="$SCHWELLE_BLOCKS" -v sa="$SCHWELLE_FEHLLOGIN" \
    '$2 >= sb || $3 >= sa { print $1 }' "$TMP/acc_neu")"
anzahl_ips="$(wc -l <"$TMP/acc_neu")"

melden=0
if [ "$erstlauf" -eq 0 ] && [ -s "$TMP/acc_neu" ]; then
    if [ -n "$ausloeser" ] || [ "$anzahl_ips" -ge "$SCHWELLE_IPS" ]; then
        melden=1
    fi
fi

# Sendepause einhalten (im Probelauf nicht — der soll ja gerade zeigen, was da ist).
ruhe="$(ruhezeit_fuer "$eskalation")"
if [ "$modus" != "dry-run" ] && [ "$melden" -eq 1 ] \
   && [ "$letzter_bericht" -gt 0 ] && [ $((JETZT - letzter_bericht)) -lt "$ruhe" ]; then
    melden=0   # zählt weiter mit, meldet aber noch nicht
fi

# ------------------------------------------------------------------
# Bericht — er ist die Ausgabe des Cron-Jobs und damit die Mail an root.
# ------------------------------------------------------------------
if [ "$melden" -eq 1 ] || { [ "$modus" = "dry-run" ] && [ -s "$TMP/acc_neu" ]; }; then
    if [ "$modus" = "dry-run" ]; then
        echo "fussballcal — Probelauf über das gesamte Log (nichts wird gespeichert)"
    else
        echo "fussballcal: gehäufte Fehlversuche am Eintrage-Formular"
    fi
    echo
    echo "Server:   $(hostname -f 2>/dev/null || hostname 2>/dev/null || echo '?')"
    echo "Quelle:   $NGINX_LOG"
    echo "Stand:    $(date '+%F %T')"
    echo "Schwelle: $SCHWELLE_BLOCKS Blocks oder $SCHWELLE_FEHLLOGIN Fehllogins je Adresse,"
    echo "          oder $SCHWELLE_IPS Adressen gleichzeitig."
    echo
    printf '  %-39s %7s %11s  %-19s %-19s\n' "Adresse" "Blocks" "Fehllogins" "erstmals" "zuletzt"
    sort -t"$TAB" -k2,2nr -k3,3nr "$TMP/acc_neu" |
        awk -F'\t' '{ printf "  %-39s %7d %11d  %-19s %-19s\n", $1, $2, $3, $4, $5 }'
    if [ -s "$TMP/spill" ]; then
        echo
        echo "  (weitere $(cat "$TMP/spill") Adressen nicht einzeln erfasst — Obergrenze $MAX_IPS)"
    fi
    echo
    if [ -n "$ausloeser" ]; then
        echo "Über der Schwelle: $(echo "$ausloeser" | tr '\n' ' ')"
    elif [ "$anzahl_ips" -ge "$SCHWELLE_IPS" ]; then
        echo "Über der Schwelle: keine einzelne Adresse, aber $anzahl_ips gleichzeitig."
    else
        echo "Über der Schwelle: nichts (Probelauf zeigt trotzdem alles Gefundene)."
    fi
    cat <<EOF

Was das heißt: "Blocks" sind Anfragen, die das Rate-Limit im vhost mit 429
abgewiesen hat; "Fehllogins" sind falsche Passwörter, die nginx angenommen und
abgelehnt hat. Die Kalender unter /ics/ sind von beidem nicht betroffen —
begrenzt und geschützt ist allein $PFAD.

Solange die Zahlen nicht dauerhaft steigen, ist nichts zu tun: Das Rate-Limit
macht Raten unattraktiv, und die Passwörter liegen als bcrypt vor. Wer auf
Nummer sicher gehen will, setzt ein neues:

  $SKRIPT_DIR/set_password.sh --random
EOF
    if [ "$modus" != "dry-run" ]; then
        echo
        echo "Nächste Meldung frühestens in $(( $(ruhezeit_fuer "$((eskalation + 1))") / 60 )) Minuten"
        echo "(Sendepause; mitgezählt wird in der Zwischenzeit weiter)."
    fi
fi

# ------------------------------------------------------------------
# Zustand fortschreiben
# ------------------------------------------------------------------
[ "$modus" != "dry-run" ] || exit 0

if [ "$melden" -eq 1 ]; then
    # Gemeldet ist gemeldet: Zähler zurück auf null, Eskalationsstufe hoch.
    : >"$TMP/acc_neu"
    letzter_bericht="$JETZT"
    eskalation=$((eskalation + 1))
elif [ ! -s "$TMP/acc_neu" ]; then
    # Ruhe eingekehrt — die nächste Meldung soll wieder sofort kommen dürfen.
    eskalation=0
fi

{
    echo "# Von loginwatch.sh erzeugt — Leseposition und Zwischenstand."
    echo "# Löschen ist unschädlich, hat aber eine Folge: Der nächste Lauf gilt"
    echo "# dann wieder als Erstlauf, merkt sich nur die aktuelle Stelle im Log"
    echo "# und meldet nichts. Alles davor bleibt ungemeldet."
    echo "pos $log_inode $neue_position"
    echo "report $letzter_bericht $eskalation"
    sed 's/^/ip /' "$TMP/acc_neu"
} >"$TMP/state"
chmod 640 "$TMP/state"
mv "$TMP/state" "$STATE"
