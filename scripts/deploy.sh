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
#
# Das Skript ist idempotent: es darf nach jedem `git pull` erneut laufen. Die
# aktive teams.txt wird dabei NICHT angefasst (außer mit --force-config).

set -euo pipefail

SPO_DIR="${SPO_DIR:-/srv/spielplanoffline}"
WEB_DIR="${WEB_DIR:-/var/www/fussballcal}"
LOG_FILE="${SPO_LOG:-/var/log/spielplanoffline.log}"
NGINX_CONF="/etc/nginx/sites-available/fussballcal.conf"
NGINX_LINK="/etc/nginx/sites-enabled/fussballcal.conf"

with_nginx=1
force_config=0

for arg in "$@"; do
    case "$arg" in
        --no-nginx)     with_nginx=0 ;;
        --force-config) force_config=1 ;;
        -h|--help)
            sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
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
# ------------------------------------------------------------------
install -d -m 755 "$SPO_DIR/SpielplanOffline"
cp -a "$REPO_DIR/vendor/SpielplanOffline/." "$SPO_DIR/SpielplanOffline/"
chmod +x "$SPO_DIR/SpielplanOffline/SpielplanOffline.sh"
info "SpielplanOffline nach $SPO_DIR/SpielplanOffline"

# mysetup.sh ersetzt setup.sh vollständig (Locale, convert/magick, kein "open")
install -m 644 "$REPO_DIR/scripts/mysetup.sh" "$SPO_DIR/SpielplanOffline/mysetup.sh"
info "Linux-Overrides: mysetup.sh"

# ------------------------------------------------------------------
# 3. Wrapper und Selbsttest
# ------------------------------------------------------------------
install -m 755 "$REPO_DIR/scripts/update_all.sh" "$SPO_DIR/update_all.sh"
install -m 755 "$REPO_DIR/scripts/selftest.sh"   "$SPO_DIR/selftest.sh"
info "Skripte: update_all.sh, selftest.sh"

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

# ------------------------------------------------------------------
# 5. Logdatei (nur anlegen, niemals leeren)
# ------------------------------------------------------------------
if [ ! -e "$LOG_FILE" ]; then
    : >"$LOG_FILE"
    chmod 644 "$LOG_FILE"
    info "Logdatei angelegt: $LOG_FILE"
fi

# ------------------------------------------------------------------
# 6. Weboberfläche
# ------------------------------------------------------------------
install -m 644 "$REPO_DIR/web/add_team.php" "$WEB_DIR/add_team.php"
info "Webformular: $WEB_DIR/add_team.php"

# ------------------------------------------------------------------
# 7. nginx-vhost — nur neu laden, wenn sich wirklich etwas geändert hat.
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
cat <<EOF
Fertig. Nächste Schritte:

  $SPO_DIR/selftest.sh        # OCR-Toolchain prüfen
  $SPO_DIR/update_all.sh      # Lauf sofort anstoßen
  tail -n 40 $LOG_FILE

Der Cron-Job wird separat eingerichtet (cron/crontab.example).
EOF
