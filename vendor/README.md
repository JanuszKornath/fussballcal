# vendor/ — eingebettete Drittanbieter-Tools

Hier liegt SpielplanOffline (V2.9) **fest im Repo** (vendored). Die
Installation kopiert das Tool von hier nach `/srv/spielplanoffline/` — es wird
zur Installations- oder Laufzeit **nichts** von astro.ru.nl oder anderen
externen Quellen nachgeladen.

## Lokale Patches

SpielplanOffline ist für macOS geschrieben. Drei Stellen funktionieren unter
Debian/Ubuntu nicht und sind hier **lokal gepatcht** (zwei in `runscript.awk`,
eine in `iconv.perl`). Alle drei Patches sind im Quelltext mit
`LOKALER PATCH (fussballcal)` kommentiert und werden von `scripts/selftest.sh`
geprüft.

### 1. `runscript.awk` — ImageMagick-Sicherheitsrichtlinie

Um die Datums-/Zeit-Verschleierung von fussball.de aufzulösen, rendert das Tool
die Zeichen des heruntergeladenen Webfonts in ein Bild und liest sie per OCR
zurück. Dafür rief es ImageMagick mit `label:@<datei>` auf. Debian und Ubuntu
verbieten dieses indirekte Einlesen von Dateien aber per Voreinstellung in
`/etc/ImageMagick-*/policy.xml`:

```xml
<policy domain="path" rights="none" pattern="@*"/>
```

`convert` bricht dann mit *"attempt to perform an operation not allowed by the
security policy"* ab. Ohne Bild gibt es keine OCR-Ausgabe, keine Code-Tabelle
und damit keine entschlüsselten Datums-/Zeitangaben — im Log steht dann bei
**jedem** Spiel `[FEHLER?] 0.0.0` und `Keine Zeit gefunden Kein Datum gefunden`,
während Vereinsnamen und Spielorte korrekt aussehen (die sind nicht
verschleiert).

Der Patch übergibt den Text unter Unix direkt als Argument
(`label:"$(cat '<datei>')"`) statt über `@<datei>`. Damit ist keine Lockerung
der Sicherheitsrichtlinie nötig.

### 2. `runscript.awk` — selbstregelnde Seitenlänge für die OCR-Bilder

Die Zeichen eines Fonts werden seitenweise in ein Bild gerendert, fest auf 100
Zeilen pro Seite. Fussball.de nutzt inzwischen Fonts, bei denen ImageMagick
schon vorher abbricht:

```
convert: width or height exceeds limit
```

Die Grenze steht in `policy.xml` (`resource width`/`height`, per Vorgabe 32KP).
Wieder gilt: kein Bild, keine OCR-Ausgabe, leere Code-Tabelle, keine
Datums-/Zeitangaben — bei nur *einem* der Fonts einer Seite, weshalb Teile des
Spielplans lesbar aussehen können und trotzdem jedes Datum fehlt.

Statt eine feste Zeilenzahl zu raten, prüft der Patch nach jedem `convert`, ob
tatsächlich ein Bild entstanden ist. Wenn nicht, wird die Seitenlänge halbiert
und erneut versucht (Untergrenze 2 Zeilen — `triple.awk` behandelt
`endline<=startline` als „nicht aufteilen"). Lässt sich auch das nicht rendern,
bricht die Zeichenerkennung für diesen Font ab, statt weiterzulaufen: eine
übersprungene Zeile würde die Zuordnung zwischen OCR-Ausgabe und Hexcodes
verschieben und die restliche Code-Tabelle unbrauchbar machen.

Dazu kommt: Das Bild der vorigen Seite wird jetzt vor jedem `convert` gelöscht.
Sonst gilt eine Datei aus einem früheren Lauf fälschlich als Erfolg.

### 3. `iconv.perl` — UTF-8-Ausgabe

Der Ausgabe-Dateihandle hatte keine `:utf8`-Schicht. Perl schrieb die
dekodierten Strings deshalb als Latin-1, aus `Göttingen` wurde in der `.ics`
`G\366ttingen`. RFC 5545 schreibt UTF-8 vor; Kalender-Apps zeigen sonst kaputte
Umlaute. Der Patch öffnet die Ausgabedatei mit `>:utf8`.

## Auf eine neuere Version aktualisieren

Fussball.de ändert Layout/Font-Obfuskation regelmäßig; wenn die ICS-Erzeugung
irgendwann fehlschlägt, kann eine neuere SpielplanOffline-Version nötig sein.
Update auf einem Rechner mit Internetzugang:

```bash
wget https://www.astro.ru.nl/~falcke/fussball2csv/SpielplanOffline.tar
rm -rf vendor/SpielplanOffline
tar xf SpielplanOffline.tar -C vendor/   # -> vendor/SpielplanOffline/
rm -f vendor/SpielplanOffline/._*        # macOS-Metadaten aus dem Tar entfernen
chmod +x vendor/SpielplanOffline/SpielplanOffline.sh
git add vendor/SpielplanOffline
git commit -m "SpielplanOffline auf V<x.y> aktualisieren"
```

**Wichtig:** Ein Update überschreibt die oben beschriebenen lokalen Patches.
Sie müssen danach erneut angewendet werden, sonst fehlen wieder alle Datums-
und Zeitangaben. `scripts/selftest.sh` meldet das.

Danach auf dem Server neu ausrollen (`git pull && sudo scripts/deploy.sh`, siehe
Installations-Abschnitt im Haupt-README) und prüfen, ob die
`-var`-Aufrufkonvention von `update_all.sh` noch zur neuen Version passt.

## Lizenzhinweis und Dank

SpielplanOffline stammt von **H. Falcke** und ist „thanksware". Der Autor
schreibt dazu:

> Das Programm ist „thanksware" (also kostenlos) und kann für den
> nichtkommerziellen (Amateurvereine) und privaten Bereich mit einem kurzen
> Dankeschön frei benutzt werden.

Dieses Verzeichnis liegt deshalb unverändert-in-der-Sache (bis auf die drei
oben dokumentierten Linux-Patches) mit im Repo — und der Dank geht an den
Autor: ohne sein `gawk`-Skript gäbe es fussballcal nicht.

Daraus folgt zweierlei:

* Die Lizenz des übrigen Repos (`../LICENSE`) gilt **nicht** für dieses
  Verzeichnis. Für SpielplanOffline gilt allein, was der Autor festgelegt hat.
* Wer fussballcal benutzt, benutzt damit auch SpielplanOffline — also
  nichtkommerziell, und am besten mit einem kurzen Dankeschön an den Autor.
