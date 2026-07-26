# vendor/ — eingebettete Drittanbieter-Tools

Hier liegt SpielplanOffline (V2.9) **fest im Repo** (vendored). Die
Installation kopiert das Tool von hier nach `/srv/spielplanoffline/` — es wird
zur Installations- oder Laufzeit **nichts** von astro.ru.nl oder anderen
externen Quellen nachgeladen.

## Lokale Patches

SpielplanOffline ist für macOS geschrieben. Zwei Stellen funktionieren unter
Debian/Ubuntu nicht und sind hier **lokal gepatcht**. Beide Patches sind im
Quelltext mit `LOKALER PATCH (fussballcal)` kommentiert und werden von
`scripts/selftest.sh` geprüft.

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

### 2. `iconv.perl` — UTF-8-Ausgabe

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

Danach auf dem Server neu ausrollen (siehe Installations-Abschnitt im
Haupt-README) und prüfen, ob die `-var`-Aufrufkonvention von `update_all.sh`
noch zur neuen Version passt.

## Lizenzhinweis

SpielplanOffline ist "thanksware" von H. Falcke (h.falcke@astro.ru.nl) für
private/Vereins-Nutzung. Vor Weiterverbreitung in einem **öffentlichen** Repo
ggf. kurz beim Autor nachfragen.
