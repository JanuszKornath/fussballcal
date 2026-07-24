# vendor/ — eingebettete Drittanbieter-Tools

Hier liegt SpielplanOffline **fest im Repo** (vendored). Die Installation
kopiert das Tool von hier nach `/srv/spielplanoffline/` — es wird zur
Installations- oder Laufzeit **nichts** von astro.ru.nl oder anderen externen
Quellen nachgeladen.

## Einmaliges Einchecken von SpielplanOffline

Falls `vendor/SpielplanOffline/` noch fehlt (das Archiv konnte aus dieser
Build-Umgebung heraus nicht geladen werden, astro.ru.nl ist dort gesperrt),
einmalig auf einem Rechner mit Internetzugang:

```bash
wget https://www.astro.ru.nl/~falcke/fussball2csv/SpielplanOffline.tar
tar xf SpielplanOffline.tar -C vendor/   # -> vendor/SpielplanOffline/
chmod +x vendor/SpielplanOffline/SpielplanOffline.sh
git add vendor/SpielplanOffline
git commit -m "SpielplanOffline V2.9 vendoren"
```

Danach ist das Tool dauerhaft Teil dieses Repos und jede Installation kommt
ohne Internetzugriff auf astro.ru.nl aus.

## Lizenzhinweis

SpielplanOffline ist "thanksware" von H. Falcke (h.falcke@astro.ru.nl) für
private/Vereins-Nutzung. Vor dem Einchecken in ein **öffentliches** Repo bzw.
vor Weiterverbreitung ggf. kurz beim Autor nachfragen.
