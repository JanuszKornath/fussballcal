# fussballcal — Fussball.de → ICS Kalender-Service

Automatisierter Dienst, der über SpielplanOffline (astro.ru.nl/~falcke/fussball2csv)
Spielpläne von fussball.de in ICS-Dateien umwandelt und per `webcal://` abonnierbar macht.

## Aufbau

```
fussballcal/
├── scripts/
│   ├── update_all.sh       # Cron-Wrapper: liest teams.txt, ruft SpielplanOffline auf
│   └── teams.txt.example   # Beispiel-Konfig (slug;url)
├── web/
│   └── add_team.php        # Formular zum Hinzufügen neuer Teams
├── nginx/
│   └── fussballcal.conf    # nginx vhost, inkl. text/calendar MIME-Type
└── cron/
    └── crontab.example
```

## Installation

```bash
sudo apt update
sudo apt install -y wget gawk tesseract-ocr tesseract-ocr-deu unzip cron nginx php-fpm

sudo mkdir -p /opt/spielplanoffline
cd /opt/spielplanoffline
wget https://www.astro.ru.nl/~falcke/fussball2csv/SpielplanOffline.tar
tar xf SpielplanOffline.tar
chmod +x SpielplanOffline.sh

sudo mkdir -p /var/www/fussballcal/ics
sudo cp scripts/update_all.sh /opt/spielplanoffline/
sudo cp scripts/teams.txt.example /opt/spielplanoffline/teams.txt
sudo cp web/add_team.php /var/www/fussballcal/
sudo cp nginx/fussballcal.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/fussballcal.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

sudo crontab -e   # Inhalt aus cron/crontab.example übernehmen
```

TLS-Terminierung und Domain-Routing übernimmt euer zentraler Reverse Proxy;
dieser nginx-vhost dient nur als internes Backend im LXC-Container (Port 80).

## Offene Punkte (TODO)

- [ ] Internen Aufbau von `myinput.sh` / `setup.sh` im SpielplanOffline-Tar prüfen
      und `update_all.sh` entsprechend anpassen (aktuell Platzhalter-Annahme:
      Aufruf mit URL + Output-Pfad als Parameter).
- [ ] Rechtliche Prüfung bei öffentlicher Bereitstellung mehrerer fremder Vereine
      (siehe Hinweis unten).
- [ ] `add_team.php` produktiv nur hinter Auth/Captcha betreiben, um Missbrauch
      (beliebige URLs, Massen-Submits) zu verhindern.

## Rechtlicher Hinweis

Das Tool ist laut Autor "thanksware" für private/Vereins-Nutzung gedacht. Bei
öffentlicher Weiterverbreitung für viele fremde Vereine ggf. vorher kurz beim
Autor (h.falcke@astro.ru.nl) nachfragen.
