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
# Für den Betrieb am öffentlichen Netz (siehe README):
#   sudo LISTEN_ADDR=10.0.0.42 ./deploy.sh    # Port 80 nur auf dieser Adresse
#   sudo TRUSTED_PROXY=10.0.0.1 ./deploy.sh   # nur der Reverse Proxy darf fragen
#
# Zeitzone der Webseiten (Vorgabe: die des Servers, sonst Europe/Berlin):
#   sudo WEB_TZ=Europe/Vienna ./deploy.sh
#
# Das Skript ist idempotent: es darf nach jedem `git pull` erneut laufen. Die
# aktive teams.txt wird dabei NICHT angefasst (außer mit --force-config).

set -euo pipefail

# Vom Aufrufer per Umgebung gesetzte Pfade merken, bevor die Vorgaben greifen.
# sudo setzt die Umgebung zurück (env_reset), die Overrides müssen bei der
# Eskalation weiter unten also ausdrücklich mitgegeben werden.
env_overrides=()
for var in SPO_DIR WEB_DIR SPO_LOG SPO_STATE_DIR WEB_GROUP ADMIN_USER WEB_TZ LISTEN_ADDR TRUSTED_PROXY; do
    if [ -n "${!var-}" ]; then
        env_overrides+=("$var=${!var}")
    fi
done

SPO_DIR="${SPO_DIR:-/srv/spielplanoffline}"
WEB_DIR="${WEB_DIR:-/var/www/fussballcal}"
LOG_FILE="${SPO_LOG:-/var/log/spielplanoffline.log}"
# Zwischenstand von loginwatch.sh (Leseposition im nginx-Log, mitgezählte
# Fehlversuche). Kein /tmp: der Zustand soll einen Neustart überleben.
STATE_DIR="${SPO_STATE_DIR:-/var/lib/fussballcal}"
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
# Zeitzone, in der die Webseiten "zuletzt aktualisiert" anzeigen. Leer heißt:
# die des Servers nehmen (siehe server_timezone weiter unten).
WEB_TZ="${WEB_TZ:-}"
# http-Kontext des vhosts (Rate-Limit-Zone, Real-IP, Peer-Prüfung). Debians
# nginx.conf bindet conf.d/*.conf vor sites-enabled/ ein.
NGINX_HTTP_CONF="/etc/nginx/conf.d/fussballcal.conf"
# Adresse, an die der vhost gebunden wird. Leer = alle Interfaces (Vorgabe).
LISTEN_ADDR="${LISTEN_ADDR:-}"
# Adresse des vorgelagerten Reverse Proxys. Gesetzt bedeutet: nur von dort
# werden Anfragen beantwortet, und die echten Client-IPs kommen aus
# X-Forwarded-For (sonst zählte das Rate-Limit alle Besucher als einen).
TRUSTED_PROXY="${TRUSTED_PROXY:-}"

with_nginx=1
force_config=0
reset_password=0

for arg in "$@"; do
    case "$arg" in
        --no-nginx)       with_nginx=0 ;;
        --force-config)   force_config=1 ;;
        --reset-password) reset_password=1 ;;
        -h|--help)
            sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'
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

# Zustandsverzeichnis für loginwatch.sh. 750, weil dort IP-Adressen von
# Fehlversuchen stehen — das geht nur root etwas an.
install -d -m 750 "$STATE_DIR"
info "Zustandsverzeichnis: $STATE_DIR"

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
install -m 755 "$REPO_DIR/scripts/loginwatch.sh"   "$SPO_DIR/loginwatch.sh"
# saison.sh wird von update_all.sh und selftest.sh gesourct und muss deshalb
# neben ihnen liegen — update_all.sh bricht ohne sie ab. Kein +x: sie ist eine
# Bibliothek, kein Programm.
install -m 644 "$REPO_DIR/scripts/saison.sh"        "$SPO_DIR/saison.sh"
info "Skripte: update_all.sh, selftest.sh, set_password.sh, loginwatch.sh, saison.sh"

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
SPO_STATE_DIR="\${SPO_STATE_DIR:-$STATE_DIR}"
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
#
# Zum Löschen eines Kalenders entfernt das Formular zusätzlich die ICS-Datei.
# Dafür braucht es Schreibrecht auf das VERZEICHNIS ics/ (die Dateien selbst
# gehören root, sie legt der Cron-Job an). Damit kann der Webserver dort auch
# Dateien anlegen — der vhost liefert alles unter /ics/ deshalb ausschließlich
# statisch aus (`location ^~ /ics/`), niemals über PHP-FPM.
if getent group "$WEB_GROUP" >/dev/null 2>&1; then
    chown "root:$WEB_GROUP" "$SPO_DIR/teams.txt"
    chmod 664 "$SPO_DIR/teams.txt"
    info "teams.txt beschreibbar für Gruppe $WEB_GROUP (Verzeichnis bleibt root-only)"
    chown "root:$WEB_GROUP" "$WEB_DIR/ics"
    chmod 775 "$WEB_DIR/ics"
    info "ics/ beschreibbar für Gruppe $WEB_GROUP (Löschen im Formular)"
else
    info "Gruppe $WEB_GROUP nicht vorhanden — teams.txt und ics/ bleiben root-only"
    info "  (das Webformular kann dann nichts eintragen/löschen; WEB_GROUP setzen)"
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

# Zeitzone für die Anzeige von "zuletzt aktualisiert". PHP rechnet ohne
# 'date.timezone' in der php.ini in UTC — die Übersicht zeigte die Uhrzeit des
# letzten Laufs dann um den UTC-Versatz verschoben an, während Cron-Job und
# Logdatei die lokale Uhr benutzen. Deshalb wird hier festgehalten, worauf der
# Server steht; common.php nimmt den Wert und fällt ohne ihn auf Europe/Berlin
# zurück.
server_timezone() {
    local tz=""
    if command -v timedatectl >/dev/null 2>&1; then
        tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    fi
    if [ -z "$tz" ] && [ -r /etc/timezone ]; then
        tz="$(tr -d '[:space:]' </etc/timezone)"
    fi
    if [ -z "$tz" ] && [ -e /etc/localtime ]; then
        # /etc/localtime zeigt auf .../zoneinfo/Europe/Berlin.
        tz="$(readlink -f /etc/localtime 2>/dev/null || true)"
        case "$tz" in
            */zoneinfo/*) tz="${tz##*/zoneinfo/}" ;;
            *)            tz="" ;;
        esac
    fi
    printf '%s' "$tz"
}

web_tz="$WEB_TZ"
if [ -z "$web_tz" ]; then
    web_tz="$(server_timezone)"
    case "$web_tz" in
        # Ein auf UTC stehender Mietserver ist die Werkseinstellung, keine
        # Entscheidung — und UTC ist genau die Anzeige, die hier niemand will.
        # Ein ausdrückliches WEB_TZ=UTC bleibt davon unberührt: das ist eine.
        ""|UTC|Etc/UTC|Universal|Etc/Universal|GMT|Etc/GMT)
            web_tz="Europe/Berlin" ;;
    esac
fi
if [ ! -f "/usr/share/zoneinfo/$web_tz" ]; then
    echo "WARNUNG: Zeitzone '$web_tz' kennt das System nicht — nehme Europe/Berlin." >&2
    web_tz="Europe/Berlin"
fi

cat >"$WEB_DIR/config.php" <<EOF
<?php
// Von deploy.sh erzeugt — Pfade und Zeitzone dieser Installation. Nicht von
// Hand ändern, der nächste Rollout überschreibt die Datei.
return [
    'config_file' => '$(php_quote "$SPO_DIR/teams.txt")',
    'ics_dir'     => '$(php_quote "$WEB_DIR/ics")',
    'timezone'    => '$(php_quote "$web_tz")',
];
EOF
chmod 644 "$WEB_DIR/config.php"
info "Pfade fürs Formular: $WEB_DIR/config.php (Zeitzone $web_tz)"

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

    # http-Kontext: Rate-Limit-Zone und Peer-Prüfung. Beides muss außerhalb des
    # server-Blocks stehen, deshalb eine eigene Datei unter conf.d/. Sie wird
    # hier erzeugt, weil erst der Rollout die Adresse des Reverse Proxys kennt.
    nginx_http_tmp="$(mktemp)"
    {
        cat <<'EOF'
# Von deploy.sh erzeugt — http-Kontext für fussballcal. Nicht von Hand ändern,
# der nächste Rollout überschreibt die Datei (Werte über TRUSTED_PROXY setzen).

# Bremse gegen Passwort-Raten am Formular; benutzt wird die Zone in der
# location = /add_team.php des vhosts. 10 MB fassen rund 160.000 Adressen.
limit_req_zone $binary_remote_addr zone=fussballcal_login:10m rate=1r/s;
EOF
        if [ -n "$TRUSTED_PROXY" ]; then
            cat <<EOF

# Hinter dem Reverse Proxy sieht nginx sonst nur dessen Adresse — dann teilten
# sich alle Besucher ein Rate-Limit-Konto. X-Forwarded-For wird deshalb als
# echte Client-Adresse übernommen, aber ausschließlich von $TRUSTED_PROXY:
# aus dem Netz gesetzte Header sind damit wirkungslos.
set_real_ip_from $TRUSTED_PROXY;
real_ip_header X-Forwarded-For;

# \$realip_remote_addr ist die Adresse der Gegenstelle, unabhängig von
# X-Forwarded-For. Alles außer dem Proxy (und dem Rechner selbst) weist der
# vhost mit 403 ab. geo statt map, weil geo auch Netzbereiche (10.0.0.0/24)
# versteht — map vergliche stur die Zeichenkette.
geo \$realip_remote_addr \$fussballcal_untrusted_peer {
    default 1;
EOF
            # Doppelte Einträge lässt geo nicht durchgehen ("duplicate
            # network") — der Proxy kann selbst localhost sein.
            emitted_nets=""
            for net in "$TRUSTED_PROXY" 127.0.0.1 ::1; do
                case " $emitted_nets " in
                    *" $net "*) continue ;;
                esac
                emitted_nets="$emitted_nets $net"
                printf '    %-18s 0;\n' "$net"
            done
            echo "}"
        else
            cat <<'EOF'

# TRUSTED_PROXY war beim Rollout nicht gesetzt: Der vhost antwortet jedem, der
# ihn erreicht. Wer den Dienst öffentlich betreibt, sollte das setzen —
# siehe README, "Absicherung im öffentlichen Netz".
geo $realip_remote_addr $fussballcal_untrusted_peer {
    default 0;
}
EOF
        fi
    } >"$nginx_http_tmp"

    if ! cmp -s "$nginx_http_tmp" "$NGINX_HTTP_CONF"; then
        install -d -m 755 "$(dirname "$NGINX_HTTP_CONF")"
        install -m 644 "$nginx_http_tmp" "$NGINX_HTTP_CONF"
        changed=1
        info "http-Kontext aktualisiert: $NGINX_HTTP_CONF"
    fi
    rm -f "$nginx_http_tmp"

    if [ -n "$TRUSTED_PROXY" ]; then
        info "Nur Anfragen von $TRUSTED_PROXY werden beantwortet"
    fi

    # vhost. Bei gesetztem LISTEN_ADDR wird die listen-Zeile beim Ausrollen
    # umgeschrieben — nginx kennt keine Variablen in `listen`, und die Datei im
    # Repo soll für sich allein gültig bleiben.
    vhost_tmp="$(mktemp)"
    if [ -n "$LISTEN_ADDR" ]; then
        # IPv6-Literale gehören in eckige Klammern.
        case "$LISTEN_ADDR" in
            *:*) listen_spec="[$LISTEN_ADDR]:80" ;;
            *)   listen_spec="$LISTEN_ADDR:80" ;;
        esac
        sed "s|^\([[:space:]]*\)listen 80 default_server;|\1listen $listen_spec default_server;|" \
            "$REPO_DIR/nginx/fussballcal.conf" >"$vhost_tmp"
        if ! grep -q "listen $listen_spec default_server;" "$vhost_tmp"; then
            echo "FEHLER: listen-Zeile in nginx/fussballcal.conf nicht gefunden." >&2
            rm -f "$vhost_tmp"
            exit 1
        fi
        info "vhost lauscht nur auf $listen_spec"
    else
        cat "$REPO_DIR/nginx/fussballcal.conf" >"$vhost_tmp"
    fi

    # Ändert sich die listen-Adresse, genügt ein Reload NICHT: nginx öffnet
    # beim Reload die neuen Lauschsockets, bevor es die alten schließt, und
    # `bind() to 127.0.0.1:80 failed (98: Address already in use)` gegen den
    # eigenen alten Socket auf 0.0.0.0:80 ist die Folge. Der Reload scheitert
    # dann still — `nginx -t` und `systemctl reload` melden beide Erfolg, und
    # der Dienst lauscht weiter auf allen Interfaces. Deshalb hier merken und
    # unten neu starten statt neu laden.
    listen_line() { grep -m1 -E '^[[:space:]]*listen ' "$1" 2>/dev/null || true; }
    need_restart=0
    if [ "$(listen_line "$NGINX_CONF")" != "$(listen_line "$vhost_tmp")" ]; then
        need_restart=1
    fi

    if ! cmp -s "$vhost_tmp" "$NGINX_CONF"; then
        install -m 644 "$vhost_tmp" "$NGINX_CONF"
        changed=1
        info "vhost aktualisiert: $NGINX_CONF"
    fi
    rm -f "$vhost_tmp"
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
            # systemctl, wo systemd läuft; sonst (Container ohne systemd)
            # direkt über nginx selbst.
            if [ "$need_restart" -eq 1 ]; then
                if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
                    systemctl restart nginx
                else
                    nginx -s quit 2>/dev/null || true
                    sleep 1
                    nginx
                fi
                info "nginx neu gestartet (listen-Adresse geändert)"
            else
                if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
                    systemctl reload nginx
                else
                    nginx -s reload
                fi
                info "nginx neu geladen"
            fi
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
  $SPO_DIR/loginwatch.sh --dry-run   # Fehlversuche am Formular ansehen

Die Kalenderübersicht liegt offen unter  http://<host>/
Eingetragen wird nur mit Anmeldung unter http://<host>/add_team.php
Passwort ändern: $SPO_DIR/set_password.sh [--user NAME]
$(if [ "$with_nginx" -eq 1 ] && [ -z "$TRUSTED_PROXY" ]; then cat <<'HINT'

Hinweis: TRUSTED_PROXY ist nicht gesetzt — dieser vhost beantwortet Anfragen
von jeder Gegenstelle, die ihn erreicht. Am öffentlichen Netz gehört das
gesetzt (README: "Absicherung im öffentlichen Netz").
HINT
fi)

Die Cron-Jobs werden separat eingerichtet (cron/crontab.example).
EOF
