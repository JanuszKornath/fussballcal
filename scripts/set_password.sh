#!/bin/bash
#
# set_password.sh — legt Zugangsdaten für das Eintrage-Formular an.
#
# Das Formular (add_team.php) liegt hinter der Basic-Auth des nginx-vhosts
# (nginx/fussballcal.conf, `auth_basic_user_file`). Dieses Skript pflegt genau
# diese Passwortdatei — ohne apache2-utils vorauszusetzen: es benutzt htpasswd,
# wenn vorhanden, sonst php oder openssl (eins davon ist auf einem Server, der
# diesen Dienst betreibt, immer da).
#
# Aufruf:
#   sudo ./set_password.sh                    # fragt interaktiv nach dem Passwort
#   sudo ./set_password.sh --user papa        # anderer Benutzername
#   sudo ./set_password.sh --random           # Zufallspasswort, wird ausgegeben
#   echo 'geheim' | sudo ./set_password.sh --stdin   # für Skripte
#   sudo ./set_password.sh --remove papa      # Benutzer löschen
#
# Ein bereits vorhandener Eintrag desselben Benutzers wird ersetzt, andere
# Benutzer bleiben stehen. Ein nginx-Reload ist nicht nötig: die Passwortdatei
# wird bei jeder Anfrage neu gelesen.

set -euo pipefail

HTPASSWD_FILE="${HTPASSWD_FILE:-/etc/nginx/fussballcal.htpasswd}"
# Gruppe des nginx-Workers — nur sie darf die Datei lesen.
WEB_GROUP="${WEB_GROUP:-www-data}"

user="admin"
mode="ask"        # ask | stdin | random | remove
remove_user=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)   user="${2:-}"; shift 2 ;;
        --file)   HTPASSWD_FILE="${2:-}"; shift 2 ;;
        --group)  WEB_GROUP="${2:-}"; shift 2 ;;
        --random) mode="random"; shift ;;
        --stdin)  mode="stdin"; shift ;;
        --remove) mode="remove"; remove_user="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unbekannte Option: $1 (siehe --help)" >&2
            exit 2 ;;
    esac
done

[ "$mode" = "remove" ] && user="$remove_user"

# Der Benutzername landet unescapt in einer ":"-getrennten Datei und in
# HTTP-Headern — deshalb eine enge Whitelist statt Escaping.
if [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "FEHLER: Benutzername darf nur A-Z a-z 0-9 . _ - enthalten." >&2
    exit 2
fi

if [ "$(id -u)" -ne 0 ] && [ ! -w "$(dirname "$HTPASSWD_FILE")" ]; then
    echo "FEHLER: $HTPASSWD_FILE ist nicht beschreibbar — mit sudo aufrufen." >&2
    exit 1
fi

# ------------------------------------------------------------------
# Hash erzeugen. Das Passwort geht immer über stdin, damit es nie in der
# Prozessliste (ps) auftaucht.
# ------------------------------------------------------------------
hash_password() {
    local pw="$1"

    if command -v htpasswd >/dev/null 2>&1; then
        # -n: nur ausgeben, -i: Passwort von stdin, -B: bcrypt.
        # -C 12 ist wichtig: htpasswd rechnet bcrypt sonst mit Kostenfaktor 5,
        # also rund hundertmal billiger als das, was PHP unten erzeugt. Immer
        # noch bcrypt, aber unnötig leicht durchzuprobieren.
        printf '%s' "$pw" | htpasswd -niB -C 12 "$user" | head -n 1 | cut -d: -f2-
    elif command -v php >/dev/null 2>&1; then
        # bcrypt ($2y$) versteht nginx über crypt(3) — auf Linux (libxcrypt) ist
        # das der gleiche Hash, den htpasswd -B schreiben würde.
        printf '%s' "$pw" | php -r 'echo password_hash(stream_get_contents(STDIN), PASSWORD_BCRYPT);'
    elif command -v openssl >/dev/null 2>&1; then
        # APR1-MD5: schwächer als bcrypt, aber das klassische htpasswd-Format
        # und von nginx überall unterstützt.
        printf '%s\n' "$pw" | openssl passwd -apr1 -stdin
    else
        echo "FEHLER: weder htpasswd noch php noch openssl gefunden." >&2
        return 1
    fi
}

random_password() {
    # 24 Hex-Zeichen (~96 Bit). Bewusst ohne Sonderzeichen: das Passwort wird
    # von Hand in einen Browser-Dialog getippt.
    od -An -tx1 -N12 /dev/urandom | tr -d ' \n'
}

# ------------------------------------------------------------------
# Datei neu schreiben: alter Eintrag des Benutzers raus, neuer rein.
# ------------------------------------------------------------------
write_file() {
    local new_line="${1:-}" tmp
    tmp="$(mktemp "${HTPASSWD_FILE}.XXXXXX")"
    # mktemp legt 600 an; die Zielrechte werden unten explizit gesetzt.

    if [ -f "$HTPASSWD_FILE" ]; then
        # Nur Zeilen anderer Benutzer übernehmen (grep findet nichts -> leer).
        grep -v "^${user}:" "$HTPASSWD_FILE" >>"$tmp" || true
    fi
    if [ -n "$new_line" ]; then
        printf '%s\n' "$new_line" >>"$tmp"
    fi

    chmod 640 "$tmp"
    if getent group "$WEB_GROUP" >/dev/null 2>&1; then
        chown root:"$WEB_GROUP" "$tmp" 2>/dev/null || true
    else
        echo "WARNUNG: Gruppe $WEB_GROUP gibt es nicht — nginx kann" \
             "$HTPASSWD_FILE vermutlich nicht lesen (--group setzen)." >&2
    fi
    mv "$tmp" "$HTPASSWD_FILE"
}

case "$mode" in
    remove)
        if [ ! -f "$HTPASSWD_FILE" ] || ! grep -q "^${user}:" "$HTPASSWD_FILE"; then
            echo "Benutzer '$user' steht nicht in $HTPASSWD_FILE — nichts zu tun."
            exit 0
        fi
        write_file ""
        echo "Benutzer '$user' aus $HTPASSWD_FILE entfernt."
        if [ ! -s "$HTPASSWD_FILE" ]; then
            echo "WARNUNG: Die Datei ist jetzt leer — niemand kann mehr" \
                 "Mannschaften eintragen (nginx antwortet mit 401)." >&2
        fi
        exit 0
        ;;
    random)
        password="$(random_password)"
        show_password=1
        ;;
    stdin)
        IFS= read -r password || true
        show_password=0
        if [ -z "$password" ]; then
            echo "FEHLER: leeres Passwort von stdin." >&2
            exit 2
        fi
        ;;
    ask)
        if [ ! -t 0 ]; then
            echo "FEHLER: kein Terminal für die Passwortabfrage." \
                 "--stdin oder --random benutzen." >&2
            exit 2
        fi
        read -r -s -p "Passwort für '$user': " password; echo
        read -r -s -p "Passwort wiederholen:  " password2; echo
        if [ "$password" != "$password2" ]; then
            echo "FEHLER: Passwörter stimmen nicht überein." >&2
            exit 1
        fi
        if [ -z "$password" ]; then
            echo "FEHLER: leeres Passwort." >&2
            exit 2
        fi
        show_password=0
        ;;
esac

hash="$(hash_password "$password")"
if [ -z "$hash" ]; then
    echo "FEHLER: Hash konnte nicht erzeugt werden." >&2
    exit 1
fi

write_file "${user}:${hash}"

echo "Zugangsdaten für '$user' in $HTPASSWD_FILE gespeichert."
if [ "$show_password" -eq 1 ]; then
    echo
    echo "  Benutzer:  $user"
    echo "  Passwort:  $password"
    echo
    echo "Jetzt notieren — das Passwort wird nur als Hash gespeichert und"
    echo "kann später nicht mehr angezeigt werden."
fi
