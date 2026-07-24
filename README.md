# fussballcal — Fussball.de → ICS Kalender-Service

Automatisierter Dienst, der über SpielplanOffline (von H. Falcke, ursprünglich
astro.ru.nl/~falcke/fussball2csv) Spielpläne von fussball.de in ICS-Dateien
umwandelt und per `webcal://` abonnierbar macht.

SpielplanOffline liegt **vendored unter `vendor/SpielplanOffline/` direkt in
diesem Repo**. Installation und Betrieb laden nichts von astro.ru.nl oder
anderen externen Quellen nach — alles Nötige ist Teil dieses Repos
(siehe `vendor/README.md`).

## Aufbau

```
fussballcal/
├── vendor/
│   └── SpielplanOffline/   # das Tool selbst, fest eingecheckt (kein Download!)
├── scripts/
│   ├── update_all.sh       # Cron-Wrapper: liest teams.txt, ruft SpielplanOffline auf
│   ├── mysetup.sh          # Linux-Overrides für SpielplanOffline (Locale, kein "open")
│   └── teams.txt.example   # Beispiel-Konfig (slug;url)
├── web/
│   └── add_team.php        # Formular zum Hinzufügen neuer Teams
├── nginx/
│   └── fussballcal.conf    # nginx vhost, inkl. text/calendar MIME-Type
└── cron/
    └── crontab.example
```

## Funktionsweise

SpielplanOffline (V2.9) ist eigentlich ein macOS/Windows-Tool, dessen Kern aber
ein `gawk`-Skript ist, das auch unter Linux läuft. Es lädt den Spielplan einer
Mannschaft/eines Vereins von fussball.de, liest die dort teils als Bild
gerenderten Daten per **OCR** (tesseract + ImageMagick) aus und schreibt sie als
`.ics` heraus.

Der Aufruf erfolgt **nicht** über `--flags`, sondern über eine gesourcte
Parameterdatei. `update_all.sh` erzeugt pro Team eine temporäre Parameterdatei
und ruft `./SpielplanOffline.sh -var <datei>` auf (mit `STYLE=ICS`,
`csvfile=<slug>`, `outdir=<tmp>`, `backgroundprocessing=1`). Ergebnis:
`<outdir>/<slug>.ics`, das atomar nach `/var/www/fussballcal/ics/<slug>.ics`
verschoben und via nginx als `text/calendar` ausgeliefert wird.

## Installation

Die Installation erfolgt komplett aus diesem Repo — es wird nichts aus dem
Internet nachgeladen. SpielplanOffline (V2.9) liegt fertig eingecheckt unter
`vendor/SpielplanOffline/` (Details und Update-Anleitung: `vendor/README.md`).

```bash
sudo apt update
# imagemagick (convert) und perl sind zwingend nötig – ohne convert bricht
# SpielplanOffline ab. wget braucht SpielplanOffline zur Laufzeit, um die
# Spielpläne von fussball.de zu holen.
sudo apt install -y wget gawk tesseract-ocr tesseract-ocr-deu imagemagick perl \
    unzip cron nginx php-fpm

# Repo klonen (oder Checkout aktualisieren) und Tool aus vendor/ installieren
git clone https://github.com/JanuszKornath/fussballcal.git
cd fussballcal

sudo mkdir -p /srv/spielplanoffline
sudo cp -r vendor/SpielplanOffline /srv/spielplanoffline/
sudo chmod +x /srv/spielplanoffline/SpielplanOffline/SpielplanOffline.sh

# Arbeitsverzeichnis (SpielplanOffline legt hier tmp/Fonts/Output an)
sudo mkdir -p /srv/spielplanoffline/work
sudo mkdir -p /var/www/fussballcal/ics

# Wrapper + Linux-Overrides + Beispielkonfig platzieren
sudo cp scripts/update_all.sh /srv/spielplanoffline/
sudo chmod +x /srv/spielplanoffline/update_all.sh
sudo cp scripts/mysetup.sh /srv/spielplanoffline/SpielplanOffline/mysetup.sh
sudo cp scripts/teams.txt.example /srv/spielplanoffline/teams.txt

# Logdatei für den Cron-Job (vom Cron-User beschreibbar machen)
sudo touch /var/log/spielplanoffline.log

# Web + nginx
sudo cp web/add_team.php /var/www/fussballcal/
sudo cp nginx/fussballcal.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/fussballcal.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

sudo crontab -e   # Inhalt aus cron/crontab.example übernehmen
```

Ein manueller Testlauf (zeigt sofort, ob OCR/convert/tesseract sauber laufen):

```bash
sudo /srv/spielplanoffline/update_all.sh
tail -n 40 /var/log/spielplanoffline.log
ls -l /var/www/fussballcal/ics/
```

Pfade lassen sich per Umgebungsvariablen überschreiben (`SPO_TOOL_DIR`,
`SPO_CONFIG`, `SPO_OUTDIR`, `SPO_HOME`, `SPO_START`, `SPO_END`, `SPO_LOG`).

TLS-Terminierung und Domain-Routing übernimmt euer zentraler Reverse Proxy;
dieser nginx-vhost dient nur als internes Backend im LXC-Container (Port 80).

## Offene Punkte (TODO)

- [x] Aufrufkonvention von SpielplanOffline gegen das Tar-Archiv (V2.9) verifiziert
      und `update_all.sh` darauf umgestellt (`-var`-Parameterdatei, `STYLE=ICS`).
- [x] `vendor/SpielplanOffline/` (V2.9) eingecheckt — das Repo ist damit
      self-contained, Installation und Betrieb laden nichts mehr von
      astro.ru.nl nach.
- [ ] End-to-End-Testlauf auf dem Debian-Server durchführen (in der Build-Umgebung
      ist fussball.de/astro.ru.nl gesperrt, ein Live-OCR-Lauf war dort nicht
      möglich). Fussball.de ändert sein Layout/Font-Obfuskation regelmäßig – bei
      Fehlern kann eine neuere SpielplanOffline-Version nötig sein, die dann
      wieder unter `vendor/` eingecheckt wird.
- [ ] Rechtliche Prüfung bei öffentlicher Bereitstellung mehrerer fremder Vereine
      (siehe Hinweis unten).
- [ ] `add_team.php` produktiv nur hinter Auth/Captcha betreiben, um Missbrauch
      (beliebige URLs, Massen-Submits) zu verhindern.

## Rechtlicher Hinweis

Das Tool ist laut Autor "thanksware" für private/Vereins-Nutzung gedacht. Bei
öffentlicher Weiterverbreitung für viele fremde Vereine – und auch beim
Einchecken des Tools in ein **öffentliches** Repo (`vendor/`) – ggf. vorher
kurz beim Autor (h.falcke@astro.ru.nl) nachfragen.
