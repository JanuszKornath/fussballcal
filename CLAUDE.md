# Hinweise für Claude

## Pull-Request-Workflow

- Review-Kommentare auf GitHub (auch von Bots wie gemini-code-assist) immer
  direkt auf GitHub beantworten: kurz erläutern, ob und wie der Hinweis
  umgesetzt wurde (mit Commit-Referenz), oder begründen, warum nicht.
- Erledigte Review-Threads anschließend als "resolved" markieren, damit im
  PR sichtbar ist, dass die Unterhaltung abgeschlossen ist.
- Issues in PR-Beschreibungen und Commit-Messages immer mit englischen
  Closing-Keywords verknüpfen (`Closes #30`, `Fixes #30`, `Resolves #30`).
  Deutsche Formen wie "Schließt #30" erkennt GitHub nicht – das Issue bleibt
  dann nach dem Merge offen. Der restliche Text darf deutsch bleiben.

## Tests

- Selbsttest:
  `SPO_ENV=/nonexistent SPO_TOOL_DIR="$PWD/vendor/SpielplanOffline" ./scripts/selftest.sh`
- ShellCheck: `LC_ALL=C.UTF-8 shellcheck -x scripts/*.sh`
  (`vendor/SpielplanOffline` ist Fremdcode und bleibt außen vor)
- PHP-Syntax: `php -l` über `web/*.php`
