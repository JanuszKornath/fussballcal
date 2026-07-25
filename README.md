# fussballcal — Fussball.de → ICS Kalender-Service

Automatisierter Dienst, der über SpielplanOffline (von H. Falcke, ursprünglich
astro.ru.nl/~falcke/fussball2csv) Spielpläne von fussball.de in ICS-Dateien
umwandelt und per `webcal://` abonnierbar macht.

SpielplanOffline liegt **vendored unter `vendor/SpielplanOffline/` direkt in
diesem Repo**. Installation und Betrieb laden nichts von astro.ru.nl oder
anderen externen Quellen nach — alles Nötige ist Teil dieses Repos
(siehe `vendor/README.md`).

> Kurz gesagt: Vereins-/Mannschaftslinks werden in `teams.txt` auf dem Server
> eingetragen (oder per Webformular), abonnierbar ist das Ergebnis unter
> `webcal://<host>/ics/<slug>.ics`. Details im Abschnitt
> [Benutzung](#benutzung).

## Aufbau

```
fussballcal/
├── vendor/
│   └── SpielplanOffline/   # das Tool selbst, fest eingecheckt (kein Download!)
├── scripts/
│   ├── update_all.sh       # Cron-Wrapper: liest teams.txt, ruft SpielplanOffline auf
│   ├── mysetup.sh          # Linux-Overrides für SpielplanOffline (Locale, kein "open")
│   └── teams.txt.example   # Vorlage für die Team-Liste (slug;url) -> wird bei der
│                           # Installation nach /srv/spielplanoffline/teams.txt kopiert
├── web/
│   └── add_team.php        # Formular zum Hinzufügen neuer Teams +
│                           # Übersicht aller Kalenderlinks
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

## Benutzung

### 1. Den fussball.de-Link heraussuchen

Auf [fussball.de](https://www.fussball.de/) die Mannschaft oder den Verein
suchen, deren Seite öffnen und die Adresse aus der Adresszeile des Browsers
kopieren. Unterstützt werden drei Link-Typen:

| Link-Typ | Beispiel | Ergebnis |
|---|---|---|
| Mannschaft | `https://www.fussball.de/mannschaft/<name>/-/saison/2526/team-id/<ID>` | Spielplan genau dieser Mannschaft |
| Verein | `https://www.fussball.de/verein/<name>/-/id/<ID>` | Spielplan **aller** Mannschaften des Vereins |
| Staffel | `https://www.fussball.de/spieltag/<name>/-/staffel/<ID>` | kompletter Spielplan der Staffel/Liga |

Der `#!/...`-Teil am Ende darf drin bleiben. Andere fussball.de-Seiten
(Startseite, Tabellen, Suchergebnisse) funktionieren nicht.

### 2. Den Link eintragen

Es gibt zwei Wege — beide schreiben in dieselbe Datei
`/srv/spielplanoffline/teams.txt` auf dem Server:

**a) Per Webformular** (der bequeme Weg): `http://<host>/` im Browser öffnen
(`add_team.php`), Link und Kurznamen eintragen, absenden. Das Formular
akzeptiert nur `https://www.fussball.de/`-Links.

**b) Direkt in der Datei** (z.B. für viele Teams auf einmal):

```bash
sudo nano /srv/spielplanoffline/teams.txt
```

Eine Zeile pro Kalender, Format `slug;url`:

```
# slug;url   — Zeilen mit # und Leerzeilen werden ignoriert
tsv_musterstadt_1;https://www.fussball.de/mannschaft/tsv-musterstadt-1-.../team-id/011MI...
sv_beispiel_verein;https://www.fussball.de/verein/sv-beispiel/-/id/00ES...
```

Der **slug** ist frei wählbar, darf aber nur `a-z`, `0-9`, `_` und `-`
enthalten (Großbuchstaben und Umlaute werden abgelehnt) — er wird zum
Dateinamen des Kalenders. `scripts/teams.txt.example` im Repo ist nur die
Vorlage; die aktive Konfiguration liegt unter `/srv/spielplanoffline/`
(überschreibbar per `SPO_CONFIG`).

### 3. Den Kalenderlink abrufen

Der Cron-Job läuft alle 6 Stunden (`cron/crontab.example`). Danach existiert
pro Zeile eine ICS-Datei, die unter folgender Adresse abonnierbar ist:

```
webcal://<host>/ics/<slug>.ics      # zum Klicken/Abonnieren
https://<host>/ics/<slug>.ics       # dieselbe Datei zum Herunterladen
```

Für das Beispiel oben also `webcal://<host>/ics/tsv_musterstadt_1.ics`.

**Alle Links auf einen Blick** listet die Startseite `http://<host>/`
(`add_team.php`) unterhalb des Formulars auf — mit „Abonnieren"-Link und dem
Zeitpunkt der letzten Aktualisierung. Auf dem Server direkt:

```bash
ls -l /var/www/fussballcal/ics/
```

Abonnieren in den gängigen Kalendern:

- **iOS / macOS**: `webcal://`-Link antippen/anklicken — Kalender öffnet sich
  und fragt nach dem Abo.
- **Google Kalender**: *Weitere Kalender → Per URL → `https://…/ics/<slug>.ics`*
  (Google aktualisiert Abos nur alle paar Stunden bis einmal täglich).
- **Outlook / Thunderbird**: Kalender abonnieren → die `https://`-Adresse
  einfügen.

Wichtig: Nicht die Datei herunterladen und importieren — dann bleibt der
Kalender auf dem Stand des Downloads. Nur ein *Abo* der URL aktualisiert sich
selbst.

Wenn ein Link nicht funktioniert, hilft ein Blick ins Log:

```bash
sudo /srv/spielplanoffline/update_all.sh   # Lauf sofort anstoßen
tail -n 40 /var/log/spielplanoffline.log
```

Ungültige Zeilen (falscher Slug, Nicht-fussball.de-URL) werden dort mit
Begründung protokolliert und übersprungen.

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
