#!/bin/bash
#
# deploy.sh — rollt den Inhalt dieses Repos auf den Server aus.
#
# Ersetzt die lange Kette einzelner `sudo cp`/`sudo mkdir`-Befehle aus dem
# README durch einen einzigen privilegierten Aufruf. Das ist nicht nur kürzer,
# sondern behebt auch die sudo-Mails der Form
#
#   <user> : a password is required ; TTY=pts/3 ; PWD=/srv/fussballcal ;
#            USER=root ; COMMAND=/usr/bin/cp scripts/selftest.sh /srv/…
#
# Diese Meldung kommt immer dann, wenn sudo authentifizieren müsste, aber nicht
# nachfragen darf (`sudo -n`, kein Terminal für den Prompt, abgelaufener
# sudo-Timestamp in einem Skript). Statt jeden einzelnen Befehl zu
# privilegieren, wird hier genau einmal eskaliert — siehe README, Abschnitt
# "sudo-Mails".
#
# Aufruf:
#   ./deploy.sh                 # eskaliert selbst per sudo (eine Passwortabfrage)
#   sudo ./deploy.sh            # genauso gut
#   sudo ./deploy.sh --no-nginx # vhost und nginx-Reload überspringen
#   sudo ./deploy.sh --force-config   # teams.txt mit der Vorlage überschreiben
#   sudo ./deploy.sh --reset-password # neues Zufallspasswort fürs Formular
#
# Das Skript ist idempotent: es darf nach jedem `git pull` erneut laufen. Die
# aktive teams.txt wird dabei NICHT angefasst (außer mit --force-config).

set -euo pipefail

# Vom Aufrufer per Umgebung gesetzte Pfade merken, bevor die Vorgaben greifen.
# sudo setzt die Umgebung zurück (env_reset), die Overrides müssen bei der
# Eskalation weiter unten also ausdrücklich mitgegeben werden.
env_overrides=()
for var in SPO_DIR WEB_DIR SPO_LOG WEB_GROUP ADMIN_USER; do
    if [ -n "${!var-}" ]; then
        env_overrides+=("$var=${!var}")
    fi
done

SPO_DIR="${SPO_DIR:-/srv/spielplanoffline}"
WEB_DIR="${WEB_DIR:-/var/www/fussballcal}"
LOG_FILE="${SPO_LOG:-/var/log/spielplanoffline.log}"
# Gruppe des PHP-FPM-Workers — nur teams.txt wird für sie beschreibbar.
WEB_GROUP="${WEB_GROUP:-www-data}"
NGINX_CONF="/etc/nginx/sites-available/fussballcal.conf"
NGINX_LINK="/etc/nginx/sites-enabled/fussballcal.conf"
# Debians Default-vhost; wird deaktiviert, damit fussballcal der
# default_server auf Port 80 ist (siehe Abschnitt 8).
NGINX_DEFAULT_LINK="/etc/nginx/sites-enabled/default"
# Zugangsdaten fürs Eintrage-Formular. Der Pfad steht so auch im vhost
# (nginx/fussballcal.conf, auth_basic_user_file) — beide müssen zusammenpassen.
HTPASSWD_FILE="/etc/nginx/fussballcal.htpasswd"
ADMIN_USER="${ADMIN_USER:-admin}"

with_nginx=1
force_config=0
reset_password=0

for arg in "$@"; do
    case "$arg" in
        --no-nginx)       with_nginx=0 ;;
        --force-config)   force_config=1 ;;
        --reset-password) reset_password=1 ;;
        -h|--help)
            sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unbekannte Option: $arg (siehe --help)" >&2
            exit 2 ;;
    esac
done

# ------------------------------------------------------------------
# Genau eine Rechteeskalation für den kompletten Rollout.
# ------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "Nicht als root gestartet — eskaliere einmalig per sudo."
        # Ohne Overrides bleibt der Aufruf schlicht: eine sudoers-Regel, die
        # den Skriptpfad freigibt (siehe README), greift dann weiterhin.
        # Mit Overrides führt der Weg über env(1) — sudo würde die Variablen
        # sonst verwerfen und der root-Lauf schriebe klammheimlich nach
        # /srv/spielplanoffline statt in das gewünschte Ziel.
        if [ "${#env_overrides[@]}" -gt 0 ]; then
            exec sudo -- env "${env_overrides[@]}" "$0" "$@"
        fi
        exec sudo -- "$0" "$@"
    fi
    echo "FEHLER: Dieses Skript braucht root-Rechte (sudo nicht gefunden)." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

info() { printf '  %s\n' "$*"; }

echo "fussballcal — Rollout aus $REPO_DIR"
echo "------------------------------------------------------------------"

# ------------------------------------------------------------------
# 1. Verzeichnisse
#    work/ ist das HOME für SpielplanOffline (tmp/Fonts/Output), ics/ das
#    Verzeichnis, aus dem nginx die Kalender ausliefert.
# ------------------------------------------------------------------
install -d -m 755 "$SPO_DIR" "$SPO_DIR/work" "$WEB_DIR" "$WEB_DIR/ics"
info "Verzeichnisse: $SPO_DIR, $SPO_DIR/work, $WEB_DIR/ics"

# ------------------------------------------------------------------
# 2. SpielplanOffline aus vendor/ (inklusive der Linux-Patches)
#    cp -a überschreibt die Programmdateien, lässt aber alles unberührt, was
#    zur Laufzeit dazugekommen ist.
#
#    Anschließend gehört der komplette Baum root. Der Checkout liegt in der
#    Regel einem normalen Benutzer, und `cp -a` würde dessen Eigentümerschaft
#    mitkopieren — der Cron-Job führt SpielplanOffline.sh aber als root aus.
#    Wer in den installierten Baum schreiben darf, hätte damit beim nächsten
#    Cron-Lauf root.
# ------------------------------------------------------------------
install -d -m 755 "$SPO_DIR/SpielplanOffline"
cp -a "$REPO_DIR/vendor/SpielplanOffline/." "$SPO_DIR/SpielplanOffline/"
chown -R root:root "$SPO_DIR/SpielplanOffline"
chmod -R go-w "$SPO_DIR/SpielplanOffline"
chmod +x "$SPO_DIR/SpielplanOffline/SpielplanOffline.sh"
info "SpielplanOffline nach $SPO_DIR/SpielplanOffline"

# mysetup.sh ersetzt setup.sh vollständig (Locale, convert/magick, kein "open")
install -m 644 "$REPO_DIR/scripts/mysetup.sh" "$SPO_DIR/SpielplanOffline/mysetup.sh"
info "Linux-Overrides: mysetup.sh"

# ------------------------------------------------------------------
# 3. Wrapper und Selbsttest
# ------------------------------------------------------------------
install -m 755 "$REPO_DIR/scripts/update_all.sh"    "$SPO_DIR/update_all.sh"
install -m 755 "$REPO_DIR/scripts/selftest.sh"      "$SPO_DIR/selftest.sh"
install -m 755 "$REPO_DIR/scripts/set_password.sh" "$SPO_DIR/set_password.sh"
info "Skripte: update_all.sh, selftest.sh, set_password.sh"

# Pfade dieser Installation für die installierten Skripte festhalten. Ohne das
# behielten update_all.sh und selftest.sh ihre eingebauten Vorgaben und würden
# bei einem verschobenen Rollout (SPO_DIR/WEB_DIR) ins Leere greifen — oder,
# schlimmer, die Standardinstallation daneben anfassen. Beide sourcen die Datei
# aus ihrem eigenen Verzeichnis; die `:-`-Zuweisungen lassen echten
# Umgebungsvariablen den Vortritt.
cat >"$SPO_DIR/spo.env" <<EOF
# Von deploy.sh erzeugt — Pfade dieser Installation. Nicht von Hand ändern,
# der nächste Rollout überschreibt die Datei.
SPO_TOOL_DIR="\${SPO_TOOL_DIR:-$SPO_DIR/SpielplanOffline}"
SPO_CONFIG="\${SPO_CONFIG:-$SPO_DIR/teams.txt}"
SPO_OUTDIR="\${SPO_OUTDIR:-$WEB_DIR/ics}"
SPO_HOME="\${SPO_HOME:-$SPO_DIR/work}"
SPO_LOG="\${SPO_LOG:-$LOG_FILE}"
EOF
chmod 644 "$SPO_DIR/spo.env"
info "Pfade festgehalten: $SPO_DIR/spo.env"

# ------------------------------------------------------------------
# 4. Team-Liste — die aktive Konfiguration ist tabu, solange sie existiert.
#    Ein zweiter Rollout darf die eingetragenen Kalender nicht wegwerfen.
# ------------------------------------------------------------------
if [ ! -e "$SPO_DIR/teams.txt" ]; then
    install -m 644 "$REPO_DIR/scripts/teams.txt.example" "$SPO_DIR/teams.txt"
    info "teams.txt aus der Vorlage angelegt"
elif [ "$force_config" -eq 1 ]; then
    cp -a "$SPO_DIR/teams.txt" "$SPO_DIR/teams.txt.bak"
    install -m 644 "$REPO_DIR/scripts/teams.txt.example" "$SPO_DIR/teams.txt"
    info "teams.txt überschrieben (Sicherung: teams.txt.bak)"
else
    info "teams.txt existiert bereits — unverändert gelassen"
fi

# Das Webformular (add_team.php) hängt Zeilen an teams.txt an und braucht dafür
# Schreibrecht auf die DATEI. Das Verzeichnis bleibt bewusst root-only: dort
# liegen update_all.sh und der Vendor-Baum, die der Cron-Job als root ausführt.
# Über teams.txt lässt sich nichts einschleusen — update_all.sh nimmt nur Slugs
# aus [a-z0-9_-] und fussball.de-URLs an und reicht die URL als Variable weiter.
if getent group "$WEB_GROUP" >/dev/null 2>&1; then
    chown "root:$WEB_GROUP" "$SPO_DIR/teams.txt"
    chmod 664 "$SPO_DIR/teams.txt"
    info "teams.txt beschreibbar für Gruppe $WEB_GROUP (Verzeichnis bleibt root-only)"
else
    info "Gruppe $WEB_GROUP nicht vorhanden — teams.txt bleibt root-only"
    info "  (das Webformular kann dann nichts eintragen; WEB_GROUP setzen)"
fi

# ------------------------------------------------------------------
# 5. Logdatei (nur anlegen, niemals leeren)
# ------------------------------------------------------------------
if [ ! -e "$LOG_FILE" ]; then
    # Bei verschobenem SPO_LOG kann das Verzeichnis noch fehlen; ohne diesen
    # Schritt bräche der Rollout hier mitten drin ab.
    log_dir="$(dirname "$LOG_FILE")"
    [ -d "$log_dir" ] || install -d -m 755 "$log_dir"
    : >"$LOG_FILE"
    chmod 644 "$LOG_FILE"
    info "Logdatei angelegt: $LOG_FILE"
fi

# ------------------------------------------------------------------
# 6. Weboberfläche
#    index.php ist die öffentliche Kalenderübersicht, add_team.php das
#    Formular hinter der Basic-Auth (siehe Abschnitt 7), common.php der
#    gemeinsame Unterbau beider Seiten.
# ------------------------------------------------------------------
install -m 644 "$REPO_DIR/web/common.php"   "$WEB_DIR/common.php"
install -m 644 "$REPO_DIR/web/index.php"    "$WEB_DIR/index.php"
install -m 644 "$REPO_DIR/web/add_team.php" "$WEB_DIR/add_team.php"
info "Webseiten: $WEB_DIR/{index,add_team,common}.php"

# Pendant zu spo.env für die PHP-Seite: ohne diese Datei zeigte das Formular
# bei verschobenem Rollout weiter auf /srv/spielplanoffline und schriebe in
# eine teams.txt, die der Cron-Job gar nicht liest.
# In PHP-Strings müssen Backslash und einfaches Anführungszeichen escapt werden.
php_quote() { printf "%s" "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"; }
cat >"$WEB_DIR/config.php" <<EOF
<?php
// Von deploy.sh erzeugt — Pfade dieser Installation. Nicht von Hand ändern,
// der nächste Rollout überschreibt die Datei.
return [
    'config_file' => '$(php_quote "$SPO_DIR/teams.txt")',
    'ics_dir'     => '$(php_quote "$WEB_DIR/ics")',
];
EOF
chmod 644 "$WEB_DIR/config.php"
info "Pfade fürs Formular: $WEB_DIR/config.php"

# ------------------------------------------------------------------
# 7. Zugangsdaten für das Eintrage-Formular
#    add_team.php liegt im vhost hinter auth_basic. Fehlt die Passwortdatei,
#    antwortet nginx dort mit 500 — deshalb wird sie beim ersten Rollout mit
#    einem Zufallspasswort angelegt und einmalig ausgegeben. Ein zweiter
#    Rollout fasst vorhandene Zugangsdaten nicht an (außer --reset-password).
# ------------------------------------------------------------------
new_credentials=""
if [ -d "$(dirname "$HTPASSWD_FILE")" ]; then
    if [ "$reset_password" -eq 1 ] || [ ! -s "$HTPASSWD_FILE" ]; then
        if new_credentials="$(HTPASSWD_FILE="$HTPASSWD_FILE" WEB_GROUP="$WEB_GROUP" \
                bash "$REPO_DIR/scripts/set_password.sh" \
                     --user "$ADMIN_USER" --random 2>&1)"; then
            info "Zugangsdaten erzeugt: $HTPASSWD_FILE (Benutzer $ADMIN_USER)"
        else
            echo "WARNUNG: Zugangsdaten konnten nicht angelegt werden:" >&2
            echo "$new_credentials" >&2
            echo "  -> $SPO_DIR/set_password.sh von Hand aufrufen." >&2
            new_credentials=""
        fi
    else
        info "Zugangsdaten vorhanden: $HTPASSWD_FILE (unverändert)"
    fi
else
    info "$(dirname "$HTPASSWD_FILE") fehlt — keine Zugangsdaten angelegt"
fi

# ------------------------------------------------------------------
# 8. nginx-vhost — nur neu laden, wenn sich wirklich etwas geändert hat.
# ------------------------------------------------------------------
if [ "$with_nginx" -eq 1 ] && [ -d "$(dirname "$NGINX_CONF")" ]; then
    changed=0
    if ! cmp -s "$REPO_DIR/nginx/fussballcal.conf" "$NGINX_CONF"; then
        install -m 644 "$REPO_DIR/nginx/fussballcal.conf" "$NGINX_CONF"
        changed=1
        info "vhost aktualisiert: $NGINX_CONF"
    fi
    if [ ! -e "$NGINX_LINK" ]; then
        ln -s "$NGINX_CONF" "$NGINX_LINK"
        changed=1
        info "vhost aktiviert: $NGINX_LINK"
    fi
    # Debians mitgelieferte Default-Site muss weg: Sie ist der default_server
    # auf Port 80 und würde beim Zugriff über die IP die nginx-Welcome-Page
    # statt fussballcal ausliefern. Seit fussballcal.conf selbst
    # 'listen 80 default_server' deklariert, scheitert sonst zusätzlich
    # 'nginx -t' mit "duplicate default server for 0.0.0.0:80".
    if [ -e "$NGINX_DEFAULT_LINK" ]; then
        rm -f "$NGINX_DEFAULT_LINK"
        changed=1
        info "Debian-Default-Site deaktiviert: $NGINX_DEFAULT_LINK"
    fi
    if [ "$changed" -eq 1 ]; then
        if nginx -t; then
            systemctl reload nginx
            info "nginx neu geladen"
        else
            echo "FEHLER: 'nginx -t' schlägt fehl — kein Reload." >&2
            exit 1
        fi
    else
        info "nginx-Konfiguration unverändert"
    fi
elif [ "$with_nginx" -eq 1 ]; then
    info "nginx nicht gefunden — vhost übersprungen"
fi

echo "------------------------------------------------------------------"

if [ -n "$new_credentials" ]; then
    echo
    echo "=== Zugangsdaten für /add_team.php ==============================="
    echo "$new_credentials"
    echo "=================================================================="
    echo
fi

cat <<EOF
Fertig. Nächste Schritte:

  $SPO_DIR/selftest.sh        # OCR-Toolchain prüfen
  $SPO_DIR/update_all.sh      # Lauf sofort anstoßen
  tail -n 40 $LOG_FILE

Die Kalenderübersicht liegt offen unter  http://<host>/
Eingetragen wird nur mit Anmeldung unter http://<host>/add_team.php
Passwort ändern: $SPO_DIR/set_password.sh [--user NAME]

Der Cron-Job wird separat eingerichtet (cron/crontab.example).
EOF
