# fussballcal — Fussball.de → ICS Kalender-Service

Automatisierter Dienst, der über SpielplanOffline (von H. Falcke, ursprünglich
astro.ru.nl/~falcke/fussball2csv) Spielpläne von fussball.de in ICS-Dateien
umwandelt und per `webcal://` abonnierbar macht.

Gedacht ist das für den Amateurbereich: Ein Verein (oder eine Familie mit drei
Mannschaften im Haushalt) stellt sich die Spielpläne einmal auf einen kleinen
Server, und alle Beteiligten abonnieren sie in ihrer Kalender-App, statt jede
Woche auf fussball.de nachzusehen. Für **nichtkommerzielle** Nutzung — siehe
[Lizenz und Dank](#lizenz-und-dank).

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
│   ├── loginwatch.sh       # Cron-Job: meldet gehäufte Fehlversuche am Formular
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
[Fehlersuche](#fehlersuche-keine-datums-zeitangaben-im-kalender).

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

**Vorausgesetzt wird ein Debian-artiges System** (entwickelt und betrieben auf
Debian 12/13 bzw. Ubuntu) mit nginx und PHP-FPM. Auf anderen Distributionen
läuft der eigentliche Kern genauso — es sind Shell, gawk, ImageMagick,
tesseract und PHP —, aber drei Pfade in `deploy.sh` und im vhost sind
Debian-typisch und müssen dann angepasst werden:
`/etc/nginx/sites-available` + `sites-enabled` (RHEL-artige Systeme kennen nur
`conf.d/`), der Socket `/run/php/php-fpm.sock` und die Webserver-Gruppe
`www-data` (überschreibbar per `WEB_GROUP`). Ein Rechner mit 1 GB RAM reicht;
Rechenzeit braucht nur die OCR, und die läuft alle sechs Stunden für ein paar
Sekunden pro Mannschaft.

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
| `/srv/spielplanoffline/{update_all.sh,selftest.sh,set_password.sh,loginwatch.sh}` | Wrapper, Selbsttest, Passwortverwaltung und die Auswertung der Fehlversuche (ausführbar) |
| `/srv/spielplanoffline/teams.txt` | Team-Liste — **nur wenn sie noch nicht existiert**; für die Webserver-Gruppe beschreibbar (664), damit `add_team.php` Zeilen anhängen kann |
| `/srv/spielplanoffline/spo.env` | die Pfade dieser Installation; `update_all.sh` und `selftest.sh` lesen sie |
| `/srv/spielplanoffline/work/` | Arbeitsverzeichnis (tmp/Fonts/Output) |
| `/var/www/fussballcal/{index.php,add_team.php,common.php,ics/}` | Übersichtsseite, Formular und Kalenderverzeichnis; `ics/` ist für die Webserver-Gruppe beschreibbar (775), damit das Formular Kalender löschen kann |
| `/var/www/fussballcal/config.php` | dieselben Pfade für die Webseiten (Pendant zu `spo.env`) |
| `/etc/nginx/fussballcal.htpasswd` | Zugangsdaten fürs Formular — **nur wenn sie noch nicht existieren**; beim ersten Rollout wird ein Zufallspasswort erzeugt und einmalig ausgegeben |
| `/etc/nginx/sites-{available,enabled}/fussballcal.conf` | vhost, danach `nginx -t` + Reload; Debians Default-Site wird dabei deaktiviert (sonst kommt die nginx-Welcome-Page statt fussballcal) |
| `/etc/nginx/conf.d/fussballcal.conf` | http-Kontext des vhosts: Rate-Limit-Zone fürs Formular und die Proxy-Prüfung (`TRUSTED_PROXY`) — wird bei **jedem** Rollout neu geschrieben |
| `/var/lib/fussballcal/` | Zwischenstand von `loginwatch.sh` (Leseposition im nginx-Log, mitgezählte Fehlversuche); `750`, weil dort IP-Adressen stehen |
| `/var/log/spielplanoffline.log` | Logdatei (wird nie geleert) |

Optionen: `--no-nginx` (vhost und Reload überspringen, z.B. wenn der vhost von
Hand angepasst wurde), `--force-config` (teams.txt aus der Vorlage
überschreiben, Sicherung als `teams.txt.bak`) und `--reset-password` (neues
Zufallspasswort fürs Formular). Ziele lassen sich über `SPO_DIR`, `WEB_DIR` und
`SPO_LOG` verschieben; `WEB_GROUP` (Vorgabe `www-data`) ist die Gruppe des
PHP-FPM-Workers, `ADMIN_USER` (Vorgabe `admin`) der Benutzername fürs Formular.
`LISTEN_ADDR` und `TRUSTED_PROXY` gehören zum Betrieb am öffentlichen Netz und
sind unten beschrieben.

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
Das Zeitfenster, in dem Spiele in den Kalender wandern, ergibt sich ohne weitere
Angabe aus der Saison in der URL der jeweiligen Zeile. `SPO_SAISON_VORLAUF`,
`SPO_SAISON_NACHLAUF`, `SPO_SAISON_KARENZ` und `SPO_SAISON_RANDABSTAND` stellen
es und die Saisonerkennung ein, `SPO_START`/`SPO_END` setzen beides außer Kraft
und geben ein festes Fenster für alle Zeilen vor. Einzelheiten unter
[Woran das Tool das Saisonende erkennt](#woran-das-tool-das-saisonende-erkennt--und-woran-nicht).

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

### TLS: ein Reverse Proxy gehört davor

Der vhost aus diesem Repo lauscht auf **Port 80, ohne TLS** — und dabei bleibt
es: Zertifikate, Domain-Routing und HTTPS sind nicht Teil dieses Projekts.
Daraus folgen zwei Betriebsarten, und nur zwei:

**Im eigenen Netz** (Heimnetz, Vereins-LAN, VPN) reicht der Dienst, wie er ist.
Abonniert wird über `http://` bzw. `webcal://` auf die lokale Adresse, ein
Proxy ist nicht nötig.

**Aus dem Internet erreichbar** nur **hinter einem Reverse Proxy**, der TLS
terminiert (nginx, Traefik, Caddy, HAProxy, ein Fertig-Setup auf dem Router …)
und auf Port 80 dieses Rechners weiterleitet. fussballcal ist dann internes
Backend. Genau für diesen Aufbau sind `LISTEN_ADDR` und `TRUSTED_PROXY` da
(siehe [Absicherung im öffentlichen Netz](#absicherung-im-öffentlichen-netz)).

Ohne TLS davor gehört der Dienst nicht ins offene Internet: Die Zugangsdaten
des Eintrage-Formulars gingen bei Basic Auth sonst praktisch im Klartext (nur
base64-kodiert) über die Leitung.

> TLS direkt in diesen vhost zu legen — etwa per `certbot --nginx` — ist nicht
> vorgesehen und wird hier auch nicht beschrieben: `deploy.sh` schreibt
> `/etc/nginx/sites-available/fussballcal.conf` bei **jedem** Rollout aus dem
> Repo neu, jede von Hand oder von certbot ergänzte TLS-Konfiguration wäre
> beim nächsten `git pull && sudo scripts/deploy.sh` wieder weg. Wer das
> trotzdem will, pflegt den vhost ab dann selbst und rollt nur noch mit
> `--no-nginx` aus.

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
sudo /srv/spielplanoffline/set_password.sh                    # Passwort für "admin" ändern
sudo /srv/spielplanoffline/set_password.sh --user trainer     # weiteren Benutzer anlegen
sudo /srv/spielplanoffline/set_password.sh --random           # Zufallspasswort erzeugen und anzeigen
sudo /srv/spielplanoffline/set_password.sh --remove trainer   # Benutzer löschen
```

Ein nginx-Reload ist danach nicht nötig — die Datei wird bei jeder Anfrage neu
gelesen. Gehasht wird mit `htpasswd -B -C 12` (bcrypt), falls installiert, sonst
über `php` (ebenfalls bcrypt) oder `openssl passwd -apr1`; `apache2-utils` muss
dafür nicht nachinstalliert werden. Das `-C 12` ist kein Detail: `htpasswd`
rechnet bcrypt sonst mit Kostenfaktor 5, also rund hundertmal billiger.

Gegen Passwort-Raten steht vor dem Formular ein Rate-Limit — Basic Auth kennt
selbst keine Sperre nach n Fehlversuchen. Erlaubt ist im Schnitt eine Anfrage
pro Sekunde mit kurzen Spitzen bis fünf, danach antwortet nginx mit `429`. Die
öffentliche Übersicht und die `ics`-Dateien sind davon nicht betroffen.

Zwei Dinge, die diese Anmeldung *nicht* leistet: Die Zugangsdaten gehen bei
Basic Auth nur base64-kodiert über die Leitung — das ist in Ordnung, solange
irgendwo davor TLS terminiert wird (siehe
[TLS](#tls-ein-reverse-proxy-gehört-davor)); ohne TLS gehört
der Dienst nicht ins Internet. Und die fertigen Kalender bleiben absichtlich
öffentlich: wer die `ics`-Adresse kennt, kann sie abonnieren. Geschützt ist nur
das *Eintragen* und *Löschen*.

### Wenn jemand am Formular klopft

Geloggt werden Fehlversuche schon immer, und zwar von nginx selbst: Ein
abgewiesener Versuch landet als `limiting requests … by zone
"fussballcal_login"` im `/var/log/nginx/error.log` (und als `429` im
`access.log`), ein falsches Passwort als `password mismatch`. Nur sieht das
niemand — deshalb liest `loginwatch.sh` beides aus:

```bash
sudo /srv/spielplanoffline/loginwatch.sh --dry-run   # ganzes Log ansehen
sudo /srv/spielplanoffline/loginwatch.sh --status    # aktueller Zwischenstand
```

Als Cron-Job (viertelstündlich, siehe `cron/crontab.example`) **schweigt das
Skript im Normalfall vollständig**. Nur wenn eine Schwelle reißt, schreibt es
einen Bericht auf die Standardausgabe — und was ein Cron-Job ausgibt, mailt
cron an root. Das Skript verschickt also selbst keine Mail, kennt keinen MTA
und braucht kein `mail`-Binary; wohin die Meldung geht, entscheidet allein
`MAILTO` in der crontab.

Ohne Schwellen wäre das unbrauchbar: Bei `rate=1r/s` erzeugt schon ein
gemächlicher Angreifer mit zwei Anfragen pro Sekunde rund **86.000**
abgewiesene Anfragen am Tag — pro Ereignis eine Mail, und `/var/mail/root`
läuft die Platte voll. Gemeldet wird deshalb erst:

| Auslöser | Vorgabe | Variable |
|---|---|---|
| Blocks (`429`) einer Adresse | ab 20 | `LOGINWATCH_BLOCKS` |
| Fehllogins einer Adresse | ab 10 | `LOGINWATCH_AUTHFAILS` |
| verschiedene Adressen gleichzeitig | ab 3 | `LOGINWATCH_IPS` |
| Sendepause nach einer Meldung | 1 h, verdoppelt sich je Folgemeldung bis 24 h | `LOGINWATCH_COOLDOWN` |
| Beobachtungsfenster | 24 h | `LOGINWATCH_WINDOW` |

Während der Sendepause geht nichts verloren — es wird weitergezählt und kommt
in der nächsten Meldung mit. Aus einem tagelangen Angriff werden so eine
Handvoll Mails statt hunderttausender. Übersteuern lässt sich das direkt in der
crontab-Zeile:

```cron
*/15 * * * * LOGINWATCH_BLOCKS=50 /srv/spielplanoffline/loginwatch.sh
```

Zwei Dinge werden bewusst **nicht** gezählt: die Zeile `no user/password was
provided for basic authentication` — die entsteht bei jedem ganz normalen
Seitenaufruf, bevor der Browser nach Zugangsdaten fragt —, und Fehlversuche
anderer vhosts derselben nginx-Instanz. Beides zu zählen hieße, Fehlalarme zu
melden. Der Selbsttest prüft genau das unter `[3] Fehlversuche am Formular`.

Und was ist mit **fail2ban**? Das setzt einen Paketfilter voraus und wäre hier
am wichtigsten Punkt wirkungslos: Hinter einem Reverse Proxy kommt die
TCP-Verbindung vom Proxy, nicht vom Angreifer. `set_real_ip_from` sorgt zwar
dafür, dass im Log die echte Client-Adresse steht, aber eine Firewall-Regel auf
diese Adresse greift ins Leere — Pakete kommen von dort nie an. Wirksam wäre
fail2ban nur auf dem Proxy selbst. Wer den Dienst ohne Proxy im flachen Netz
betreibt, kann es zusätzlich einsetzen; die Logzeilen oben sind die passenden
Muster dafür.

### Absicherung im öffentlichen Netz

Sobald der Dienst aus dem Internet erreichbar ist — also hinter einem Reverse
Proxy, siehe oben —, sind zwei Fragen zu klären: **worauf lauscht nginx** und
**wer darf fragen**. Für beides gibt es eine Variable beim Rollout:

```bash
sudo LISTEN_ADDR=10.0.0.42 TRUSTED_PROXY=10.0.0.0/24 scripts/deploy.sh
```

Beide sind **optional**: Ohne sie verhält sich der Rollout wie bisher — Port 80
auf allen Adressen, keine Herkunftsprüfung. Im Repo steht keine Adresse, und
abgefragt wird auch nichts; wer die Variablen nicht setzt, merkt von beidem
nichts.

**`LISTEN_ADDR`** bindet Port 80 an genau eine Adresse — auf allen anderen
Interfaces existiert der Port danach nicht mehr (`ss -ltn` zeigt es). Das ist
die wirksamste Einzelmaßnahme, wenn der Rechner außer dem internen Netz noch
irgendetwas anderes sieht. Ohne die Variable bleibt es bei allen Adressen.

> Nur mit **fester** Adresse benutzen. Hängt die Adresse an DHCP oder
> kommt das Netz erst nach nginx hoch, findet nginx beim Start nichts zum
> Binden und verweigert den Dienst. Im Zweifel `LISTEN_ADDR` weglassen und die
> Abgrenzung der Firewall überlassen.

> Ein Wechsel der `listen`-Adresse braucht einen **Neustart**, keinen Reload:
> nginx öffnet beim Reload die neuen Lauschsockets, bevor es die alten
> schließt, und scheitert dann am eigenen Socket (`Address already in use`) —
> still, denn `nginx -t` und `systemctl reload` melden trotzdem Erfolg.
> `deploy.sh` erkennt den Fall und startet in dem Fall neu.

**`TRUSTED_PROXY`** ist die Herkunft des Reverse Proxys — besser gleich als
Netz (`10.0.0.0/24`) statt als einzelne Adresse: Das überlebt einen
Adresswechsel des Proxys, und eine Einzel-IP hieße, dass der Dienst nach so
einem Wechsel niemandem mehr antwortet. Gesetzt bewirkt sie zweierlei:
Anfragen von jeder anderen Gegenstelle beantwortet der vhost mit `403` — auch
auf `/ics/` —, und die echten Client-Adressen werden aus `X-Forwarded-For`
übernommen, aber nur von dieser Herkunft. Ohne das zählte das Rate-Limit oben
alle Besucher als einen einzigen (nginx sähe ja nur den Proxy), und ein
einzelner Angreifer sperrte damit alle anderen aus. Ist die Variable nicht
gesetzt, antwortet der vhost wie bisher jedem — `deploy.sh` weist am Ende
darauf hin.

Beides ersetzt **keine Firewall**; es ist die Schicht darunter, falls der
Rechner doch einmal direkt erreichbar ist. Die harte Grenze zieht die Firewall
davor — auf dem Host, dem Router oder im Container selbst:

```bash
# nftables: Port 80 nur vom Reverse Proxy
sudo nft add rule inet filter input tcp dport 80 ip saddr != 10.0.0.1 drop
# oder mit ufw
sudo ufw allow from 10.0.0.1 to any port 80 proto tcp
sudo ufw deny 80/tcp
```

Was am Ende zählt, steht damit an drei Stellen, und keine davon ist überflüssig:
Routing/NAT entscheidet, was den Rechner überhaupt erreicht, die Firewall
filtert den Rest, und `LISTEN_ADDR`/`TRUSTED_PROXY` sorgen dafür, dass nginx
auch dann nicht antwortet, wenn die beiden anderen einmal falsch stehen.

Was sonst noch mehr bringt als jede Änderung an diesem Code: automatische
Sicherheitsupdates für nginx und PHP (`unattended-upgrades`).

### Fehlersuche: es erscheint die nginx-Welcome-Page

Wer beim Aufruf der Server-IP die Seite *"Welcome to nginx!"* sieht, hat
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

Mannschafts- und Staffellinks sind **saisongebunden**: fussball.de vergibt die
`team-id` bzw. die `staffel`-ID pro Saison neu, bei Mannschaftslinks steht die
Saison zusätzlich in der Adresse (`.../saison/2526/...`). Ein solcher Eintrag
gilt damit nur für diese eine Saison. Ein **Vereinslink** dagegen ist es nicht —
er enthält weder Saison noch team-id, und sein Kalender wandert von selbst in
die neue Saison. Was zum Saisonwechsel zu tun ist, steht unter
[Saisonwechsel](#5-saisonwechsel).

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

### 5. Saisonwechsel

fussball.de vergibt pro Saison eigene Mannschafts- und Staffellinks — die Saison
steckt in der Adresse (`.../saison/2526/...`), und die `team-id` gilt nur für
eine Spielzeit. Ein solcher Kalender bildet deshalb immer nur die Spiele **einer**
Saison ab; er hört zum Saisonende einfach auf, statt mit den neuen Spielen
weiterzulaufen. Vereinslinks (`.../verein/.../id/<ID>`) sind davon ausgenommen:
sie enthalten keine Saison, ihr Kalender läuft von selbst weiter.

> **Was die Saison eingrenzt, ist das Datumsfenster — nicht die `team-id`.** Das
> ist im Betrieb nachgemessen: ein Kalender der Saison 26/27 lieferte auch die
> letzten, bereits gespielten Partien vom Juni 2026 mit, also die Reste der
> Vorsaison. Die abgefragte Druckansicht filtert erkennbar allein nach
> `datum-von`/`datum-bis`, die `team-id` entscheidet nur, um *welche* Mannschaft
> es geht. Deshalb überlappen die Fenster benachbarter Saisons um den Vor- und
> Nachlauf: am Anfang stehen ein paar Spiele der alten, am Ende ein paar der
> neuen Saison im Kalender. Das ist bekannt und in Kauf genommen — es sind
> gespielte Partien in der Vergangenheit. Wer es exakt haben will, setzt
> `SPO_SAISON_VORLAUF=0` und `SPO_SAISON_NACHLAUF=0`; dann ist das Fenster genau
> das Spieljahr vom 1.7. bis zum 30.6.

Zum Saisonwechsel deshalb pro Mannschaft:

1. Auf fussball.de den Link der **neuen** Saison heraussuchen (Schritt 1).
2. Ihn unter einem eigenen Kurznamen eintragen, z.B. `tsv_musterstadt_1_2627`
   (Schritt 2). Der alte Eintrag kann stehen bleiben — sein Kalender ist dann
   das Archiv der vergangenen Saison — oder nach Schritt 4 gelöscht werden.
3. Die neue Adresse an die Abonnenten weitergeben bzw. sie auf die Startseite
   verweisen, wo der neue Kalender automatisch auftaucht.

**Bestehende Abos wechseln nicht von selbst auf die neue Saison**: Wer den
Kalender der alten Saison abonniert hat, muss den neuen Link zusätzlich
abonnieren und das alte Abo in seiner Kalender-App entfernen. Beide
Webseiten weisen darauf hin — die Startseite für die Abonnenten, das
Formular für die, die Links eintragen.

Wer stattdessen den Slug behalten will, kann in `teams.txt` auch nur die URL
der bestehenden Zeile auf die neue Saison umschreiben. Dann bleibt die Abo-URL
gleich und die Abonnenten müssen nichts tun — allerdings verschwindet damit
auch der alte Spielplan aus dem Kalender, sobald der Cron-Job das nächste Mal
läuft.

### Woran das Tool das Saisonende erkennt — und woran nicht

**Mit Gewissheit kann es nicht sagen, wann eine Saison vorbei ist.** Das liegt
nicht am Tool, sondern an der Quelle: fussball.de liefert eine Druckansicht des
Spielplans für ein angefragtes Datumsfenster, mit Datum, Uhrzeit, Heim, Gast,
Ort, Ergebnis, Wettbewerb und Spielnummer. Kein Saisonende, keine Spieltagszahl,
keine Tabelle. Das einzige Signal ist damit die **Abwesenheit von Spielen** — und
die ist nicht endgültig: nach dem letzten Ligaspieltag folgen Nachhol-,
Relegations- und Pokalspiele, und ein verlegtes Spiel verschwindet zunächst ganz
aus der Ausgabe, um später mit neuem Datum wieder aufzutauchen.

Was das Tool deshalb tut: es unterscheidet vier Zustände pro Kalender und legt
sie neben der `.ics` in einer `<slug>.state` ab. Die Startseite zeigt sie als
Abzeichen, das Log schreibt sie im Klartext.

| Zustand | Bedeutung |
|---|---|
| `LAUFEND` | Es stehen noch Spiele an. |
| `SAISONENDE_VERMUTLICH` | Termine vorhanden, aber keiner mehr in der Zukunft, und das letzte liegt länger als `SPO_SAISON_KARENZ` (21 Tage) zurück. |
| `KEINE_SPIELE_MEHR_ERWARTET` | Zusätzlich ist das Saisonfenster abgelaufen. |
| `VORSAISON` | Noch keine Spiele angesetzt — am Saisonanfang normal, kein Fehler. |
| `LEER_UNERWARTET` | Keine Spiele mitten in der Saison. Verdächtig; die Ausgabe wird verworfen. |

Der Nutzen liegt weniger in der Vorhersage als in der **Unterscheidung**: vorher
war „keine Termine" gleichbedeutend mit „OCR kaputt", der Kalender fror ein und
das Log füllte sich alle sechs Stunden mit derselben `FEHLER:`-Zeile. Jetzt sagt
das Log, welcher der beiden Fälle vorliegt.

Bei `SAISONENDE_VERMUTLICH` und `KEINE_SPIELE_MEHR_ERWARTET` hängt das Tool
zusätzlich einen **Ganztags-Termin an den Kalender** („Saison 25/26 ist beendet —
neuen Kalender abonnieren"). Das ist der einzige Kanal, der bestehende Abos
erreicht: die Abonnenten stehen nirgends. Kommen doch noch Spiele, verschwindet
der Hinweis beim nächsten Lauf von selbst — die `.ics` wird jedes Mal neu
erzeugt.

Eine leere Ausgabe wird **nie veröffentlicht**, aus keinem Grund. Die bestehende
Datei ist der Spielplan der Saison; sie gegen einen leeren Kalender zu tauschen
nähme den Abonnenten auch noch das Archiv.

#### Das Abfragefenster

Abgefragt wird pro Zeile das Saisonfenster aus der URL. Die Spielordnungen
definieren das Spieljahr einheitlich als **1. Juli bis 30. Juni** — von der
Bundesliga bis in die Kreisliga. Im Normalbetrieb wird das auch eingehalten:
Relegation, Entscheidungs- und Pokalendspiele liegen im Mai und Juni, und selbst
der Nachholstau eines harten Winters wird bis zum Saisonende abgearbeitet.

Das Fenster bekommt deshalb nur einen Monat Luft an jeder Seite:
`SPO_SAISON_VORLAUF` (Vorgabe 1 Monat) davor, `SPO_SAISON_NACHLAUF` (Vorgabe
1 Monat) danach. Für die Saison 25/26 wird also `2025-06-01 .. 2026-07-31`
abgefragt. Der Nachlauf rechnet auf den 1. Juli der Folgesaison und zieht einen
Tag ab, damit jeder Wert auf einem Monatsende landet — `2 months` ergibt den
31.08., `6 months` den 31.12.

Größer sollte das Fenster nicht sein: es reichte sonst tief in die Folgesaison,
deren Pokalrunden schon in der zweiten Julihälfte beginnen, und sammelte damit
Spiele ein, die gar nicht mehr zu dieser Saison gehören. Das ist keine Theorie —
die Abfrage filtert allein nach Datum, siehe den Kasten unter
[Saisonwechsel](#5-saisonwechsel).

Klebt das letzte gefundene Spiel am Rand des Fensters (näher als
`SPO_SAISON_RANDABSTAND`, Vorgabe 14 Tage), schreibt das Tool eine Warnung ins
Log — dann ist `SPO_SAISON_NACHLAUF` zu erhöhen.

**Die eine bekannte Ausnahme ist die Pandemie.** Der BFV hat die Saison 2019/20
von der Bayernliga abwärts bis zum **30. Juni 2021** gestreckt, weil der
Spielbetrieb erst ab September 2020 wieder möglich war und in den meisten Ligen
noch 10 bis 17 Spieltage ausstanden; die Saison 2020/21 fiel dafür aus. So etwas
ist aus den Daten **nicht** erkennbar: nach der Unterbrechung klafft eine Lücke,
das letzte sichtbare Spiel liegt weit vor dem Fensterende, und die Randwarnung
oben schlägt deshalb nicht an. Tritt der Fall wieder ein, deckt ihn eine
Variable ab — für den BFV-Zeitraum exakt:

```bash
SPO_SAISON_NACHLAUF="12 months"   # Saison 19/20 -> Fenster bis 2021-06-30
```

Wer stattdessen ein festes Fenster für alle Zeilen will, setzt
`SPO_START`/`SPO_END`; die schalten die Saisonlogik ganz ab.

Zeilen ohne erkennbare Saison in der URL (Vereinslinks) behalten das alte
rollierende Fenster (−2 Monate bis +12 Monate) und bekommen keinen Saisonstatus.

Die Klassifikation lässt sich ohne fussball.de prüfen:
`scripts/selftest.sh` testet sie unter `[2] Saisonlogik` gegen synthetische
Kalenderdateien.

## Fehlersuche: keine Datums-/Zeitangaben im Kalender

**Symptom** — im Log stehen alle Spiele mit Vereinsnamen, Spielort und
Heim/Auswärts korrekt da, aber ohne Datum und Uhrzeit:

```
28      [FEHLER?] 0.0.0         SV Beispiel - TSV Musterstadt  (Beispieldorf A-Platz, …) [Auswärts]
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
# nur das Deploy-Skript, kein allgemeines NOPASSWD.
# <benutzer> durch das Konto ersetzen, unter dem der Rollout läuft.
<benutzer> ALL=(root) NOPASSWD: /srv/fussballcal/scripts/deploy.sh
```

Achtung: `deploy.sh` kopiert Dateien aus dem Checkout als root. Wer in den
Checkout schreiben darf, ist mit dieser Regel faktisch root — vertretbar, wenn
der Benutzer ohnehin der Server-Administrator ist, sonst besser bei der
Passwortabfrage bleiben.

## Was erfahrungsgemäß bricht

Fussball.de ändert Layout und Font-Obfuskation regelmäßig — das ist der einzige
Teil dieses Aufbaus, der von außen kaputtgehen kann. Wenn die Datumsangaben
irgendwann wieder fehlen, führt der Abschnitt
[Fehlersuche](#fehlersuche-keine-datums-zeitangaben-im-kalender) durch die
Eingrenzung; im Zweifel ist eine neuere SpielplanOffline-Version nötig, die
dann wieder unter `vendor/` eingecheckt wird (Patches nicht vergessen, siehe
`vendor/README.md`).

Zwei Dinge gehören zum Betrieb, stehen aber außerhalb dieses Repos:
automatische Sicherheitsupdates für nginx und PHP (`unattended-upgrades`) und
eine Firewall vor Port 80 (siehe
[Absicherung im öffentlichen Netz](#absicherung-im-öffentlichen-netz)).

## Mitwirken

Fehlerberichte und Pull Requests sind willkommen — besonders Anpassungen für
andere Distributionen und Rückmeldungen, wenn fussball.de wieder etwas geändert
hat. Zwei Bitten: Änderungen an `vendor/SpielplanOffline/` bleiben auf das
Nötigste beschränkt und werden im Quelltext mit `LOKALER PATCH (fussballcal)`
markiert, damit `scripts/selftest.sh` sie findet und ein Versionsupdate
nachvollziehbar bleibt. Und wer am Rollout schraubt, prüft bitte, dass
`deploy.sh` idempotent bleibt.

## Lizenz und Dank

**Dank** geht an **H. Falcke**, den Autor von *SpielplanOffline*
(`vendor/SpielplanOffline/`, urspr. astro.ru.nl/~falcke/fussball2csv). Ohne
sein `gawk`-Skript, das die Font-Verschleierung von fussball.de auflöst, gäbe
es dieses Projekt nicht. Er schreibt dazu selbst:

> Das Programm ist „thanksware" (also kostenlos) und kann für den
> nichtkommerziellen (Amateurvereine) und privaten Bereich mit einem kurzen
> Dankeschön frei benutzt werden.

Wer fussballcal einsetzt, sagt also am besten auch ihm kurz danke.

**Lizenz.** Aus diesen Bedingungen folgt die Lizenz dieses Repos: Der eigene
Code (`scripts/`, `web/`, `nginx/`, `cron/` und diese Dokumentation) darf frei
benutzt, verändert und weitergegeben werden — **für private Zwecke und für
Amateurvereine. Kommerzielle Nutzung ist nicht gestattet.** Der volle Text
steht in [`LICENSE`](LICENSE). Für `vendor/SpielplanOffline/` gilt weiterhin
allein das, was der Autor dort festgelegt hat (siehe `vendor/README.md`) — die
Lizenz dieses Repos erstreckt sich nicht darauf.

Kommerziell heißt hier: verkaufen, als Teil eines kostenpflichtigen oder
werbefinanzierten Angebots betreiben, oder sonst überwiegend zum Geldverdienen
einsetzen. Ein Verein, der seine Spielpläne für seine Mitglieder bereitstellt,
ist damit ausdrücklich nicht gemeint — auch dann nicht, wenn er einen
Mitgliedsbeitrag erhebt.

**Zu den Daten.** Die erzeugten Kalender enthalten Spielplandaten von
fussball.de (DFB). Dieses Projekt steht in keiner Verbindung zum DFB und ist
weder von ihm unterstützt noch autorisiert. Es holt dieselben Seiten, die auch
ein Browser lädt, alle sechs Stunden je eingetragener Mannschaft — der
sinnvolle Rahmen ist der eigene Verein bzw. die eigenen Kinder, nicht das
systematische Absaugen ganzer Verbandsdatenbestände. Wer den Dienst für viele
fremde Vereine öffentlich anbietet, klärt die Zulässigkeit besser vorher selbst
ab.
