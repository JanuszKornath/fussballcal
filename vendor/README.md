# vendor/ — eingebettete Drittanbieter-Tools

Hier liegt SpielplanOffline (V2.9) **fest im Repo** (vendored). Die
Installation kopiert das Tool von hier nach `/srv/spielplanoffline/` — es wird
zur Installations- oder Laufzeit **nichts** von astro.ru.nl oder anderen
externen Quellen nachgeladen.

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

Danach auf dem Server neu ausrollen (siehe Installations-Abschnitt im
Haupt-README) und prüfen, ob die `-var`-Aufrufkonvention von `update_all.sh`
noch zur neuen Version passt.

## Lizenzhinweis

SpielplanOffline ist "thanksware" von H. Falcke (h.falcke@astro.ru.nl) für
private/Vereins-Nutzung. Vor Weiterverbreitung in einem **öffentlichen** Repo
ggf. kurz beim Autor nachfragen.
