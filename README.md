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
> `webcal://<host>/ics/<slug>.ics`. Löschen geht denselben Weg — im Formular
> per Knopf, auf dem Server per Editor. Details im Abschnitt
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
│   ├── set_password.sh     # Zugangsdaten für das Eintrage-Formular (Basic Auth)
│   ├── mysetup.sh          # Linux-Overrides für SpielplanOffline (Locale, kein "open")
│   └── teams.txt.example   # Vorlage für die Team-Liste (slug;url) -> wird bei der
│                           # Installation nach /srv/spielplanoffline/teams.txt kopiert
├── web/
│   ├── index.php           # öffentliche Übersicht aller Kalenderlinks (ohne Login)
│   ├── add_team.php        # Formular zum Hinzufügen und Löschen (nur mit Login)
│   └── common.php          # gemeinsamer Unterbau beider Seiten
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
# Spielpläne von fussball.de zu holen. fontconfig und fonts-dejavu-core
# braucht nur der Selbsttest: er sucht per `fc-list` einen TrueType-Font, um
# den OCR-Durchstich zu prüfen, und überspringt den Test sonst.
sudo apt install -y wget gawk tesseract-ocr tesseract-ocr-deu imagemagick perl \
    cron nginx php-fpm fontconfig fonts-dejavu-core

# Repo klonen (oder Checkout aktualisieren), z.B. nach /srv/fussballcal
git clone https://github.com/JanuszKornath/fussballcal.git
cd fussballcal

# Alles ausrollen: SpielplanOffline aus vendor/, Wrapper, Selbsttest,
# Linux-Overrides, Beispielkonfig, Webseiten, Zugangsdaten, nginx-vhost, Logdatei.
sudo scripts/deploy.sh

sudo crontab -e   # Inhalt aus cron/crontab.example übernehmen
```

`deploy.sh` macht alle privilegierten Schritte in **einem** sudo-Aufruf —
deshalb gibt es genau eine Passwortabfrage statt fünfzehn (siehe
[sudo-Mails](#sudo-mails-a-password-is-required)). Was es anlegt:

| Ziel | Inhalt |
|---|---|
| `/srv/spielplanoffline/SpielplanOffline/` | das Tool aus `vendor/` inkl. Patches und `mysetup.sh` |
| `/srv/spielplanoffline/{update_all.sh,selftest.sh,set_password.sh}` | Wrapper, Selbsttest und Passwortverwaltung (ausführbar) |
| `/srv/spielplanoffline/teams.txt` | Team-Liste — **nur wenn sie noch nicht existiert**; für die Webserver-Gruppe beschreibbar (664), damit `add_team.php` Zeilen anhängen kann |
| `/srv/spielplanoffline/spo.env` | die Pfade dieser Installation; `update_all.sh` und `selftest.sh` lesen sie |
| `/srv/spielplanoffline/work/` | Arbeitsverzeichnis (tmp/Fonts/Output) |
| `/var/www/fussballcal/{index.php,add_team.php,common.php,ics/}` | Übersichtsseite, Formular und Kalenderverzeichnis; `ics/` ist für die Webserver-Gruppe beschreibbar (775), damit das Formular Kalender löschen kann |
| `/var/www/fussballcal/config.php` | dieselben Pfade für die Webseiten (Pendant zu `spo.env`) |
| `/etc/nginx/fussballcal.htpasswd` | Zugangsdaten fürs Formular — **nur wenn sie noch nicht existieren**; beim ersten Rollout wird ein Zufallspasswort erzeugt und einmalig ausgegeben |
| `/etc/nginx/sites-{available,enabled}/fussballcal.conf` | vhost, danach `nginx -t` + Reload; Debians Default-Site wird dabei deaktiviert (sonst kommt die nginx-Welcome-Page statt fussballcal) |
| `/var/log/spielplanoffline.log` | Logdatei (wird nie geleert) |

Optionen: `--no-nginx` (vhost und Reload überspringen, z.B. wenn der vhost von
Hand angepasst wurde), `--force-config` (teams.txt aus der Vorlage
überschreiben, Sicherung als `teams.txt.bak`) und `--reset-password` (neues
Zufallspasswort fürs Formular). Ziele lassen sich über `SPO_DIR`, `WEB_DIR` und
`SPO_LOG` verschieben; `WEB_GROUP` (Vorgabe `www-data`) ist die Gruppe des
PHP-FPM-Workers, `ADMIN_USER` (Vorgabe `admin`) der Benutzername fürs Formular.

**Das Passwort aus dem ersten Rollout notieren** — es steht nur einmal auf dem
Bildschirm und wird danach nur noch als Hash aufbewahrt. Verloren? Dann
`sudo /srv/spielplanoffline/set_password.sh` (siehe
[Zugang zum Formular](#zugang-zum-formular)).

Beschreibbar für den Webserver sind ausschließlich `teams.txt` und das
Verzeichnis `ics/` (Löschen einer Datei braucht Schreibrecht auf das
Verzeichnis, nicht auf die Datei). `/srv/spielplanoffline/` selbst bleibt
root: dort liegen `update_all.sh` und der Vendor-Baum, die der Cron-Job als
root ausführt; wären sie für den Webserver schreibbar, hätte ein Treffer in
`add_team.php` direkt root zur Folge. Über `teams.txt` selbst lässt sich
nichts einschleusen: `update_all.sh` akzeptiert nur Slugs aus `[a-z0-9_-]`
und fussball.de-URLs und reicht die URL als Variable statt als Text in die
Parameterdatei. Und weil `ics/` im Docroot liegt und für den Webserver
beschreibbar ist, liefert der vhost alles unterhalb von `/ics/` per
`location ^~ /ics/` ausnahmslos statisch aus — ohne das Präfix `^~` würde ein
`.php` in diesem Verzeichnis an PHP-FPM gehen. `config.php` und `common.php`
sperrt der vhost zusätzlich per `deny all`: beide werden von den Seiten
eingebunden, haben als eigene Adresse aber nichts im Netz zu suchen.

Erst die Toolchain prüfen, dann einen manuellen Lauf anstoßen:

```bash
sudo /srv/spielplanoffline/selftest.sh    # ImageMagick, tesseract, Patches
sudo /srv/spielplanoffline/update_all.sh
tail -n 40 /var/log/spielplanoffline.log
ls -l /var/www/fussballcal/ics/
```

Beide Skripte lesen die Pfade dieser Installation aus `spo.env` (von
`deploy.sh` erzeugt); gesetzte Umgebungsvariablen haben Vorrang:
`SPO_TOOL_DIR`, `SPO_CONFIG`, `SPO_OUTDIR`, `SPO_HOME`, `SPO_LOG`, dazu
`SPO_ENV` für die Datei selbst und `SPO_LOCK` für die Lockdatei.
`SPO_START` und `SPO_END` verschieben das Zeitfenster, in dem Spiele in den
Kalender wandern — ohne Angabe reicht es von zwei Monaten in der Vergangenheit
bis zwölf Monate in die Zukunft.

Zwei Läufe gleichzeitig gibt es nicht: `update_all.sh` hält ein `flock` auf
`SPO_LOCK` und bricht mit *„Update läuft bereits"* ab, wenn ein Lauf länger
dauert als der Cron-Takt.

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

### Zugang zum Formular

Der Dienst hat zwei Seiten, und nur eine davon ist geschützt:

| Seite | Zugang | Inhalt |
|---|---|---|
| `http://<host>/` (`index.php`) | **offen** | Liste aller Kalender mit Abo-Link und Stand der letzten Aktualisierung |
| `http://<host>/ics/<slug>.ics` | **offen** | die Kalender selbst — Abos funktionieren nur ohne Login |
| `http://<host>/add_team.php` | **Login** | Formular zum Eintragen — dazu dieselbe Liste, aber mit *Löschen*-Knöpfen |

Die Anmeldung ist HTTP-Basic-Auth: nginx prüft sie in der `location =
/add_team.php` gegen `/etc/nginx/fussballcal.htpasswd` (siehe
`nginx/fussballcal.conf`), der Browser fragt Benutzer und Passwort in seinem
eigenen Dialog ab. Zusätzlich reicht der vhost den angemeldeten Namen als
`fastcgi_param REMOTE_USER` an PHP durch: fehlt er, weigert sich `add_team.php`
und zeigt einen Konfigurationsfehler an, statt ein offenes Formular
auszuliefern. Wer den vhost selbst pflegt (`--no-nginx`) oder einen anderen
Webserver benutzt, muss also beides einrichten — `auth_basic` **und** den
`REMOTE_USER`-Parameter.

Zugangsdaten pflegt `set_password.sh` (die Datei liegt außerhalb des
Web-Verzeichnisses und gehört `root:www-data`, Rechte `640`):

```bash
sudo /srv/spielplanoffline/set_password.sh                 # Passwort für "admin" ändern
sudo /srv/spielplanoffline/set_password.sh --user papa     # weiteren Benutzer anlegen
sudo /srv/spielplanoffline/set_password.sh --random        # Zufallspasswort erzeugen und anzeigen
sudo /srv/spielplanoffline/set_password.sh --remove papa   # Benutzer löschen
```

Ein nginx-Reload ist danach nicht nötig — die Datei wird bei jeder Anfrage neu
gelesen. Gehasht wird mit `htpasswd -B` (bcrypt), falls installiert, sonst über
`php` (ebenfalls bcrypt) oder `openssl passwd -apr1`; `apache2-utils` muss
dafür nicht nachinstalliert werden.

Zwei Dinge, die diese Anmeldung *nicht* leistet: Die Zugangsdaten gehen bei
Basic Auth nur base64-kodiert über die Leitung — das ist hier in Ordnung, weil
der vorgelagerte Reverse Proxy TLS terminiert und der vhost selbst nur
containerintern auf Port 80 lauscht; ohne TLS davor sollte der Dienst nicht ins
Internet. Und die fertigen Kalender bleiben absichtlich öffentlich: wer die
`ics`-Adresse kennt, kann sie abonnieren. Geschützt ist nur das *Eintragen*.

### Fehlersuche: es erscheint die nginx-Welcome-Page

Wer beim Aufruf der Container-IP die Seite *"Welcome to nginx!"* sieht, hat
noch Debians Default-Site aktiv. Beim Zugriff über die IP passt kein
`server_name`, also liefert nginx den vhost aus, der auf Port 80 als
`default_server` markiert ist — und das ist dann die Default-Site, nicht
fussballcal. (`server_name _` in `fussballcal.conf` ist kein Wildcard, sondern
nur ein bewusst ungültiger Platzhaltername; er gewinnt nichts gegen einen
`default_server`.)

`deploy.sh` entfernt die Default-Site selbst, ein erneuter Lauf genügt also:

```bash
sudo scripts/deploy.sh
```

Von Hand ist es derselbe Schritt:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Wer den vhost mit `--no-nginx` selbst pflegt, muss die Default-Site selbst
loswerden: `fussballcal.conf` deklariert `listen 80 default_server`, und
solange Debians Default-Site danebenliegt, scheitert `nginx -t` mit
*"duplicate default server for 0.0.0.0:80"*.

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

**a) Per Webformular** (der bequeme Weg): `http://<host>/add_team.php` im
Browser öffnen — der Browser fragt nach Benutzer und Passwort (siehe
[Zugang zum Formular](#zugang-zum-formular)) —, Link und Kurznamen eintragen,
absenden. Das Formular akzeptiert nur `https://www.fussball.de/`-Links und
höchstens 200 Einträge in `teams.txt` (Obergrenze gegen Missbrauch, danach
meldet es *„Maximale Anzahl an Teams erreicht"*). Von der öffentlichen
Startseite führt unten ein Link dorthin.

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
(`index.php`) auf — mit „Abonnieren"-Link und dem Zeitpunkt der letzten
Aktualisierung. Diese Seite braucht keine Anmeldung und kann so an alle
weitergegeben werden, die nur abonnieren wollen. Auf dem Server direkt:

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

### 4. Einen Kalender wieder löschen

**a) Per Webformular**: `http://<host>/add_team.php` öffnen (mit Anmeldung,
siehe [Zugang zum Formular](#zugang-zum-formular)), in der Liste *Vorhandene
Kalender* neben dem Eintrag auf *Löschen* klicken und die Rückfrage
bestätigen. Das entfernt in einem Schritt die Zeile aus
`/srv/spielplanoffline/teams.txt` **und** die Datei
`/var/www/fussballcal/ics/<slug>.ics`. Kommentare und die übrigen Einträge in
`teams.txt` bleiben unangetastet.

Auf der öffentlichen Startseite (`index.php`) gibt es die Knöpfe bewusst
nicht: Sie bekommt die Liste ohne CSRF-Token und rendert damit keine
Lösch-Formulare; verarbeitet wird ein Löschen ohnehin nur in `add_team.php`,
also hinter der Anmeldung.

**b) Direkt auf dem Server**:

```bash
sudo nano /srv/spielplanoffline/teams.txt          # Zeile löschen
sudo rm /var/www/fussballcal/ics/<slug>.ics
```

Beide Schritte gehören zusammen: Wird nur die Zeile entfernt, bleibt die
ICS-Datei liegen und nginx liefert sie unverändert weiter aus — der Kalender
friert also ein, statt zu verschwinden. Genau deshalb macht das Formular
beides auf einmal.

Ein Abo, das schon in einer Kalender-App eingerichtet ist, muss **dort**
separat entfernt werden; nach dem Löschen auf dem Server liefert die URL nur
noch einen 404.

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
- [ ] Rechtliche Prüfung bei öffentlicher Bereitstellung mehrerer fremder Vereine
      (siehe Hinweis unten).
- [x] `add_team.php` liegt hinter HTTP-Basic-Auth, die Kalenderübersicht
      (`index.php`) und die `ics`-Dateien bleiben offen zugänglich (siehe
      [Zugang zum Formular](#zugang-zum-formular)). Massen-Submits durch
      Unbefugte sind damit erledigt; ein Captcha braucht es nicht mehr. Das
      Löschen liegt hinter derselben Anmeldung und zusätzlich hinter einem
      CSRF-Token — Basic-Auth allein schützt nicht davor, dass eine fremde
      Seite eine Anfrage im Namen des angemeldeten Benutzers auslöst.

Fussball.de ändert Layout und Font-Obfuskation regelmäßig. Wenn die
Datumsangaben irgendwann wieder fehlen, führt der Abschnitt
[Fehlersuche](#fehlersuche-keine-datumszeitangaben-im-kalender) durch die
Eingrenzung; im Zweifel ist eine neuere SpielplanOffline-Version nötig, die
dann wieder unter `vendor/` eingecheckt wird (Patches nicht vergessen).

## Rechtlicher Hinweis

Das Tool ist laut Autor "thanksware" für private/Vereins-Nutzung gedacht. Bei
öffentlicher Weiterverbreitung für viele fremde Vereine – und auch beim
Einchecken des Tools in ein **öffentliches** Repo (`vendor/`) – ggf. vorher
kurz beim Autor (h.falcke@astro.ru.nl) nachfragen.
