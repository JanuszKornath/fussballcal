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
│   ├── deploy.sh           # rollt Repo-Inhalt nach /srv und /var/www aus
│   │                       # (ein einziger sudo-Aufruf, idempotent)
│   ├── update_all.sh       # Cron-Wrapper: liest teams.txt, ruft SpielplanOffline auf
│   ├── selftest.sh         # prüft die OCR-Toolchain (ImageMagick, tesseract, Patches)
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
Mannschaft/eines Vereins von fussball.de und schreibt ihn als `.ics` heraus.

Datum und Uhrzeit verschleiert fussball.de dabei über einen eigenen Webfont:
Im HTML stehen nur Codepoints aus dem Unicode-Private-Use-Bereich
(`&#xE00B;&#xE017;…`), erst der Font macht daraus lesbare Zahlen. Vereinsnamen
und Spielorte stehen dagegen im Klartext. SpielplanOffline lädt deshalb den
Font, rendert die Codepoints mit **ImageMagick** zu einem Bild, liest sie per
**tesseract** (OCR) zurück und baut daraus eine Übersetzungstabelle. Genau diese
Kette ist der empfindliche Teil des Aufbaus — siehe
[Fehlersuche](#fehlersuche-keine-datumszeitangaben-im-kalender).

Drei Stellen des Tools funktionieren unter Debian/Ubuntu nicht und sind in
`vendor/` **lokal gepatcht** (Details: `vendor/README.md`). Nach einem Update
von SpielplanOffline müssen die Patches erneut angewendet werden.

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

# Repo klonen (oder Checkout aktualisieren), z.B. nach /srv/fussballcal
git clone https://github.com/JanuszKornath/fussballcal.git
cd fussballcal

# Alles ausrollen: SpielplanOffline aus vendor/, Wrapper, Selbsttest,
# Linux-Overrides, Beispielkonfig, Webformular, nginx-vhost, Logdatei.
sudo scripts/deploy.sh

sudo crontab -e   # Inhalt aus cron/crontab.example übernehmen
```

`deploy.sh` macht alle privilegierten Schritte in **einem** sudo-Aufruf —
deshalb gibt es genau eine Passwortabfrage statt fünfzehn (siehe
[sudo-Mails](#sudo-mails-a-password-is-required)). Was es anlegt:

| Ziel | Inhalt |
|---|---|
| `/srv/spielplanoffline/SpielplanOffline/` | das Tool aus `vendor/` inkl. Patches und `mysetup.sh` |
| `/srv/spielplanoffline/{update_all.sh,selftest.sh}` | Wrapper und Selbsttest (ausführbar) |
| `/srv/spielplanoffline/teams.txt` | Team-Liste — **nur wenn sie noch nicht existiert**; für die Webserver-Gruppe beschreibbar (664), damit `add_team.php` Zeilen anhängen kann |
| `/srv/spielplanoffline/spo.env` | die Pfade dieser Installation; `update_all.sh` und `selftest.sh` lesen sie |
| `/srv/spielplanoffline/work/` | Arbeitsverzeichnis (tmp/Fonts/Output) |
| `/var/www/fussballcal/{add_team.php,ics/}` | Webformular und Kalenderverzeichnis |
| `/etc/nginx/sites-{available,enabled}/fussballcal.conf` | vhost, danach `nginx -t` + Reload |
| `/var/log/spielplanoffline.log` | Logdatei (wird nie geleert) |

Optionen: `--no-nginx` (vhost und Reload überspringen, z.B. wenn der vhost von
Hand angepasst wurde) und `--force-config` (teams.txt aus der Vorlage
überschreiben, Sicherung als `teams.txt.bak`). Ziele lassen sich über
`SPO_DIR`, `WEB_DIR` und `SPO_LOG` verschieben; `WEB_GROUP` (Vorgabe
`www-data`) ist die Gruppe des PHP-FPM-Workers.

Beschreibbar für den Webserver ist ausschließlich `teams.txt` — das
Verzeichnis darüber bleibt root. Dort liegen `update_all.sh` und der
Vendor-Baum, die der Cron-Job als root ausführt; wären sie für den Webserver
schreibbar, hätte ein Treffer in `add_team.php` direkt root zur Folge. Über
`teams.txt` selbst lässt sich nichts einschleusen: `update_all.sh` akzeptiert
nur Slugs aus `[a-z0-9_-]` und fussball.de-URLs und reicht die URL als
Variable statt als Text in die Parameterdatei.

Erst die Toolchain prüfen, dann einen manuellen Lauf anstoßen:

```bash
sudo /srv/spielplanoffline/selftest.sh    # ImageMagick, tesseract, Patches
sudo /srv/spielplanoffline/update_all.sh
tail -n 40 /var/log/spielplanoffline.log
ls -l /var/www/fussballcal/ics/
```

Pfade lassen sich per Umgebungsvariablen überschreiben (`SPO_TOOL_DIR`,
`SPO_CONFIG`, `SPO_OUTDIR`, `SPO_HOME`, `SPO_START`, `SPO_END`, `SPO_LOG`).

### Änderungen aus dem Repo nachziehen

`deploy.sh` ist idempotent und darf nach jedem `git pull` erneut laufen — es
ist der einzige vorgesehene Weg, Dateien nach `/srv` zu bringen:

```bash
cd /srv/fussballcal        # der Checkout auf dem Server
git pull
sudo scripts/deploy.sh
sudo /srv/spielplanoffline/selftest.sh
```

Die eingetragenen Kalender in `/srv/spielplanoffline/teams.txt` bleiben dabei
unangetastet.

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

## Fehlersuche: keine Datums-/Zeitangaben im Kalender

**Symptom** — im Log stehen alle Spiele mit Vereinsnamen, Spielort und
Heim/Auswärts korrekt da, aber ohne Datum und Uhrzeit:

```
28      [FEHLER?] 0.0.0         Bovender SV - 1. SC Göttingen 05  (Bovenden A-Platz, …) [Auswärts]
 Keine Zeit gefunden Kein Datum gefunden
------------------------------------------------------------------------
FEHLER!!! Mindestens ein Datum stimmt nicht.
```

**Ursache** — genau diese Aufteilung (Namen gut, Datum/Zeit fehlt) zeigt, dass
die Font-Entschlüsselung gescheitert ist: Vereinsnamen stehen im HTML im
Klartext, Datum und Uhrzeit nur als Private-Use-Codepoints, die erst per OCR
lesbar werden. Häufigste Gründe:

1. **ImageMagick-Richtlinie** blockiert das Rendern (`label:@datei`). Das ist
   die Voreinstellung unter Debian/Ubuntu und war der Grund, weshalb die erste
   Installation nur leere Termine lieferte. Behoben durch den Patch in
   `vendor/SpielplanOffline/runscript.awk` — nach einem Update von
   SpielplanOffline muss er erneut angewendet werden (`vendor/README.md`).
2. **ImageMagick-Ressourcenlimit**: `convert: width or height exceeds limit`.
   Das OCR-Bild wird zu groß. Behoben durch die selbstregelnde Seitenlänge
   (ebenfalls `runscript.awk`). Zu erkennen im Log an
   `Bild konnte nicht erzeugt werden - halbiere die Seitenlaenge …` — solange
   danach Termine mit Datum erscheinen, ist das kein Fehler, sondern die
   Selbstregelung bei der Arbeit. Eine Seite kann dabei mehrere Fonts nutzen;
   fällt nur einer aus, fehlen genau die von ihm verschleierten Angaben.
3. **`tesseract-ocr-deu` fehlt** — ohne Sprachpaket liefert die OCR nichts
   Brauchbares.
4. **ImageMagick 7** installiert nur `magick` statt `convert`. `mysetup.sh`
   fängt das ab; SpielplanOffline.sh bricht sonst mit
   *"FEHLER: ImageMagick convert nicht installiert"* ab.
5. **fussball.de hat das Seitenlayout geändert.** Dann hilft nur eine neuere
   SpielplanOffline-Version (`vendor/README.md`).

Die ersten vier Punkte prüft der Selbsttest:

```bash
sudo /srv/spielplanoffline/selftest.sh
```

**Auswirkung auf den veröffentlichten Kalender** — `update_all.sh` prüft jede
frisch erzeugte `.ics`, bevor sie nach `/var/www/fussballcal/ics/` wandert
(mindestens ein Termin, kein `DTSTART` im Jahr 0000, keine `[FEHLER?]`-Marken,
gültiges UTF-8). Schlägt die Prüfung fehl, bleibt die bisherige Datei stehen —
ein veralteter Kalender ist besser als einer voller Termine am 00.00.0000. Im
Log erscheint dann `FEHLER: <slug>.ics verworfen`.

Zwischenstände eines Laufs liegen unter `/srv/spielplanoffline/work/SpielplanOffline/tmp/`
und helfen beim Eingrenzen:

| Datei | Inhalt |
|---|---|
| `spielplan-<verein>-original.html` | Seite, wie sie von fussball.de kam (noch verschleiert) |
| `spielplan-<verein>.html` | dieselbe Seite nach der Entschlüsselung — hier muss das Datum lesbar sein |
| `image-<fontnr>.1.png` | das Bild, das an die OCR geht (fehlt es, hakt ImageMagick) |
| `ocr-<fontnr>.txt` | was tesseract gelesen hat |
| `codetable-<fontnr>.txt` | Übersetzungstabelle Codepoint → Zeichen (leer = Entschlüsselung gescheitert) |

## sudo-Mails: „a password is required"

**Symptom** — an root gehen Mails dieser Form (sichtbar auch in
`/var/log/auth.log` bzw. `journalctl -t sudo`):

```
<host> : Jul 26 15:40:23 : <user> : a password is required ; TTY=pts/3 ;
    PWD=/srv/fussballcal ; USER=root ; COMMAND=/usr/bin/cp scripts/selftest.sh /srv/spielplanoffline/
```

**Bedeutung** — das ist weder ein Einbruchsversuch noch ein falsch getipptes
Passwort (das meldet sudo als *"incorrect password attempts"*). Die Meldung
kommt, wenn sudo authentifizieren **müsste**, aber nicht nachfragen **darf**:

1. `sudo -n` / `--non-interactive` — direkt oder aus einem Wrapper
   (Makefile, Deploy-Skript, Ansible ohne `become_ask_pass`).
2. Kein nutzbares Terminal für den Prompt: der Befehl steckt in einem Skript,
   dessen Eingabe aus Datei oder Pipe kommt (`ssh host 'bash -s' < setup.sh`,
   `curl … | bash`), oder er läuft aus cron/at/einem Editor-Terminal heraus.
3. Der sudo-Timestamp ist mitten in einer langen Befehlskette abgelaufen
   (Voreinstellung: 15 Minuten). Die ersten `sudo cp` laufen durch, ein
   späteres will erneut fragen — und kann es nicht.
4. Es gibt eine `NOPASSWD`-Regel, die diesen konkreten Befehl nicht abdeckt
   (`sudo -l` zeigt, was für den Benutzer erlaubt ist).

`PWD=/srv/fussballcal` und `COMMAND=…cp scripts/selftest.sh…` verraten den
Auslöser: einer der einzeln abgesetzten Kopierbefehle aus der Installations-
bzw. Update-Anleitung. Der abgebrochene `cp` bedeutet auch, dass genau diese
Datei auf dem Server **nicht** aktualisiert wurde — der Rollout war unvollständig.

**Lösung** — nicht jeden einzelnen Befehl privilegieren, sondern einmal das
Deploy-Skript:

```bash
cd /srv/fussballcal
git pull
sudo scripts/deploy.sh     # eine Passwortabfrage für den kompletten Rollout
```

Das Skript eskaliert notfalls selbst (`./scripts/deploy.sh` ohne `sudo` genügt),
bricht bei einem Fehler sofort ab (`set -euo pipefail`) und hinterlässt keinen
halben Stand mehr.

**Wenn der Rollout unbeaufsichtigt laufen soll** (Cron, CI, `ssh … <<'EOF'`),
kann man genau dieses eine Skript vom Passwort befreien:

```bash
sudo visudo -f /etc/sudoers.d/fussballcal
```

```
# nur das Deploy-Skript, kein allgemeines NOPASSWD
badmin ALL=(root) NOPASSWD: /srv/fussballcal/scripts/deploy.sh
```

Achtung: `deploy.sh` kopiert Dateien aus dem Checkout als root. Wer in den
Checkout schreiben darf, ist mit dieser Regel faktisch root — vertretbar, wenn
der Benutzer ohnehin der Server-Administrator ist, sonst besser bei der
Passwortabfrage bleiben.

## Offene Punkte (TODO)

- [x] Aufrufkonvention von SpielplanOffline gegen das Tar-Archiv (V2.9) verifiziert
      und `update_all.sh` darauf umgestellt (`-var`-Parameterdatei, `STYLE=ICS`).
- [x] `vendor/SpielplanOffline/` (V2.9) eingecheckt — das Repo ist damit
      self-contained, Installation und Betrieb laden nichts mehr von
      astro.ru.nl nach.
- [x] Erster Serverlauf lieferte Termine ohne Datum/Uhrzeit. Ursache gefunden und
      behoben: Debian/Ubuntu verbieten `label:@datei` in ImageMagick, damit
      scheiterte die OCR-Entschlüsselung der Datumsangaben (`vendor/README.md`).
      Zusätzlich schrieb `iconv.perl` die `.ics` als Latin-1 statt UTF-8.
- [x] `update_all.sh` verwirft fehlerhafte ICS-Dateien, statt einen funktionierenden
      Kalender damit zu überschreiben; `scripts/selftest.sh` prüft die Toolchain.
- [x] Zweite Ursache für fehlende Datumsangaben behoben: fussball.de nutzt
      inzwischen mehrere Obfuskations-Fonts, bei den größeren brach ImageMagick
      mit `width or height exceeds limit` ab. Die Seitenlänge der OCR-Bilder ist
      jetzt selbstregelnd (`vendor/README.md`).
- [x] Rollout in `scripts/deploy.sh` gebündelt: eine Rechteeskalation statt
      fünfzehn einzelner `sudo`-Befehle. Das beseitigt die sudo-Mails
      „a password is required" und die dadurch unvollständigen Rollouts
      (siehe [sudo-Mails](#sudo-mails-a-password-is-required)).
- [x] End-to-End-Testlauf gegen das echte fussball.de auf dem Server: am
      26.07.2026 erfolgreich, 39 Termine mit Datum und Uhrzeit. Gegen die
      Mannschaftsseite geprüft — Datum, Anstoßzeit und Paarung stimmen überein,
      inklusive der Freitags- und Samstagsspiele mit abweichenden Anstoßzeiten.

Fussball.de ändert Layout und Font-Obfuskation regelmäßig. Wenn die
Datumsangaben irgendwann wieder fehlen, führt der Abschnitt
[Fehlersuche](#fehlersuche-keine-datumszeitangaben-im-kalender) durch die
Eingrenzung; im Zweifel ist eine neuere SpielplanOffline-Version nötig, die
dann wieder unter `vendor/` eingecheckt wird (Patches nicht vergessen).
- [ ] Rechtliche Prüfung bei öffentlicher Bereitstellung mehrerer fremder Vereine
      (siehe Hinweis unten).
- [ ] `add_team.php` produktiv nur hinter Auth/Captcha betreiben, um Missbrauch
      (beliebige URLs, Massen-Submits) zu verhindern.

## Rechtlicher Hinweis

Das Tool ist laut Autor "thanksware" für private/Vereins-Nutzung gedacht. Bei
öffentlicher Weiterverbreitung für viele fremde Vereine – und auch beim
Einchecken des Tools in ein **öffentliches** Repo (`vendor/`) – ggf. vorher
kurz beim Autor (h.falcke@astro.ru.nl) nachfragen.
