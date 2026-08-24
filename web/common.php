<?php
/**
 * common.php
 *
 * Gemeinsamer Unterbau der beiden Seiten:
 *   index.php     — öffentliche Kalenderübersicht (ohne Auth)
 *   add_team.php  — Formular zum Eintragen (nur mit Auth, siehe requireUser())
 *
 * Enthält nur Definitionen und gibt selbst nichts aus.
 */

declare(strict_types=1);

// Pfade dieser Installation. scripts/deploy.sh legt config.php neben dieses
// Skript und trägt dort die tatsächlich benutzten Pfade ein — sonst zeigten die
// Seiten bei einem verschobenen Rollout weiter auf /srv/spielplanoffline und
// schrieben in eine Datei, die der Cron-Job gar nicht liest. Ohne die Datei
// gelten die Standardpfade.
$deployed = is_readable(__DIR__ . '/config.php') ? require __DIR__ . '/config.php' : [];

define('CONFIG_FILE', $deployed['config_file'] ?? '/srv/spielplanoffline/teams.txt');
define('ICS_DIR',     $deployed['ics_dir']     ?? '/var/www/fussballcal/ics');
const MAX_TEAMS = 200; // simple Obergrenze gegen Missbrauch

/**
 * Liest die Statusdatei, die update_all.sh neben die ICS legt.
 *
 * Format ist bewusst flach ("schlüssel=wert", #-Kommentare) — das Projekt
 * kommt ohne Datenbank aus. Fehlt die Datei, war noch kein Update-Lauf da;
 * dann gibt es hier ein leeres Array und die Seite zeigt keinen Saisonstatus.
 *
 * @return array<string, string>
 */
function readTeamState(string $slug): array
{
    if (preg_match('/^[a-z0-9_-]+$/', $slug) !== 1) {
        return [];
    }

    $path = ICS_DIR . '/' . $slug . '.state';
    if (!is_readable($path)) {
        return [];
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return [];
    }

    $state = [];
    foreach ($lines as $line) {
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $state[trim($key)] = trim($value);
    }

    return $state;
}

/**
 * Beschreibt den Saisonstatus eines Kalenders für die Anzeige.
 *
 * Bewusst zurückhaltend formuliert: "vermutlich beendet" ist eine Heuristik.
 * fussball.de nennt kein Saisonende — das einzige Signal ist, dass keine
 * Spiele mehr anstehen, und Nachhol- oder Pokalspiele können das zurückdrehen.
 *
 * @param array<string, string> $state
 * @return array{0: string, 1: string, 2: string}|null [CSS-Klasse, Kurztext, Erklärung]
 */
function seasonBadge(array $state): ?array
{
    $saison = $state['saison'] ?? '';
    $status = $state['status'] ?? '';

    // Ohne Saison in der URL ist der Eintrag ein Vereinslink. Der ist gar nicht
    // saisongebunden — die Abfrage an fussball.de enthält dann weder Saison noch
    // team-id, der Kalender wandert also von selbst in die neue Saison. Für den
    // wäre "Saison 25/26" schlicht falsch.
    if ($saison === '' || strlen($saison) !== 4) {
        return $status === 'LAUFEND'
            ? ['laeuft', 'nicht saisongebunden',
               'Ein Vereinslink umfasst alle Mannschaften und läuft mit der neuen '
               . 'Saison von selbst weiter — dieses Abo muss nicht gewechselt werden.']
            : null;
    }

    $label = 'Saison ' . substr($saison, 0, 2) . '/' . substr($saison, 2, 2);

    return match ($status) {
        'LAUFEND' => ['laeuft', $label, 'Es stehen noch Spiele an.'],
        'SAISONENDE_VERMUTLICH' => ['endet', $label . ' – vermutlich beendet',
            'Für diese Mannschaft steht kein Spiel mehr an. Zur neuen Saison wird '
            . 'ein neuer Kalender hier erscheinen, der zusätzlich abonniert werden muss. '
            . 'Kommen doch noch Nachhol- oder Pokalspiele, läuft dieser Kalender weiter.'],
        'KEINE_SPIELE_MEHR_ERWARTET' => ['beendet', $label . ' – beendet',
            'Das Saisonfenster ist abgelaufen, es sind keine weiteren Spiele zu '
            . 'erwarten. Der Kalender steht im Archiv dieser Seite und ändert sich '
            . 'nicht mehr; ein bestehendes Abo kann als Archiv der Saison stehen bleiben.'],
        'VORSAISON' => ['wartet', $label . ' – noch keine Spiele',
            'Der Spielplan ist auf fussball.de noch nicht veröffentlicht.'],
        default => null,
    };
}

/**
 * Gehört dieser Kalender ins Archiv?
 *
 * Nur KEINE_SPIELE_MEHR_ERWARTET — und bewusst NICHT SAISONENDE_VERMUTLICH.
 * Der Unterschied ist hier nicht kosmetisch: SAISONENDE_VERMUTLICH ist eine
 * Heuristik, die zurückspringen kann, sobald doch noch Nachhol-, Relegations-
 * oder Pokalspiele angesetzt werden (siehe scripts/saison.sh). Ein Kalender,
 * der zwischen Übersicht und Archiv hin- und herwandert, wäre schlimmer als
 * einer, der schlicht stehen bleibt: Wer ihn beim zweiten Besuch nicht mehr an
 * seinem Platz findet, hält ihn für gelöscht.
 *
 * KEINE_SPIELE_MEHR_ERWARTET setzt dagegen voraus, dass das Saisonfenster
 * abgelaufen ist, und das fällt nicht zurück — der Status ist damit endgültig.
 *
 * Ohne Saison in der URL wird er gar nicht erst vergeben: saison_status()
 * erreicht den Zweig nur mit gesetztem FENSTER_ENDE. Vereinslinks laufen also
 * weiter und bleiben in der Übersicht, wo sie hingehören.
 *
 * @param array<string, string> $state
 */
function isArchived(array $state): bool
{
    return ($state['status'] ?? '') === 'KEINE_SPIELE_MEHR_ERWARTET'
        && strlen($state['saison'] ?? '') === 4;
}

/**
 * Teilt die Kalenderliste in laufende und archivierte Einträge.
 *
 * Der laufende Teil behält die Reihenfolge aus readTeams() (nach Kurznamen).
 * Das Archiv wird nach Saison absteigend sortiert: die zuletzt beendete Saison
 * steht oben, denn nach der wird am ehesten noch gesucht. Innerhalb einer
 * Saison entscheidet wieder der Kurzname.
 *
 * @param list<array{slug: string, url: string, exists: bool, mtime: ?int,
 *                   state: array<string, string>}> $teams
 * @return array{0: list<array<string, mixed>>, 1: list<array<string, mixed>>}
 */
function splitArchived(array $teams): array
{
    $current = [];
    $archived = [];

    foreach ($teams as $team) {
        if (isArchived($team['state'])) {
            $archived[] = $team;
        } else {
            $current[] = $team;
        }
    }

    usort($archived, static function (array $a, array $b): int {
        $bySeason = strcmp($b['state']['saison'] ?? '', $a['state']['saison'] ?? '');
        return $bySeason !== 0 ? $bySeason : strcmp($a['slug'], $b['slug']);
    });

    return [$current, $archived];
}

/**
 * Liest teams.txt nach der gleichen Konvention wie update_all.sh
 * (Format "slug;url", Leerzeilen und #-Kommentare werden übersprungen) und
 * reichert jeden Eintrag mit dem Status der zugehörigen ICS-Datei an.
 *
 * @return list<array{slug: string, url: string, exists: bool, mtime: ?int,
 *                    state: array<string, string>}>
 */
function readTeams(): array
{
    if (!is_readable(CONFIG_FILE)) {
        return [];
    }

    $lines = file(CONFIG_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return [];
    }

    $teams = [];
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }

        [$slug, $url] = array_pad(explode(';', $line, 2), 2, '');
        $slug = trim($slug);
        $url  = trim($url);

        // Gleiche Slug-Whitelist wie update_all.sh – ungültige Zeilen erzeugen
        // dort auch keine ICS-Datei und werden hier gar nicht erst angezeigt.
        if ($slug === '' || preg_match('/^[a-z0-9_-]+$/', $slug) !== 1) {
            continue;
        }

        $icsPath = ICS_DIR . '/' . $slug . '.ics';
        $exists  = is_file($icsPath);

        $teams[] = [
            'slug'   => $slug,
            'url'    => $url,
            'exists' => $exists,
            'mtime'  => $exists ? (filemtime($icsPath) ?: null) : null,
            'state'  => readTeamState($slug),
        ];
    }

    usort($teams, static fn(array $a, array $b): int => strcmp($a['slug'], $b['slug']));

    return $teams;
}

/**
 * Kann das Formular einen Eintrag anhängen?
 *
 * Anhängen braucht Schreibrecht auf die DATEI; nur wenn sie noch gar nicht
 * existiert, muss das Verzeichnis beschreibbar sein. Genau so richtet
 * scripts/deploy.sh es ein: teams.txt gehört root und der Webserver-Gruppe,
 * das Verzeichnis darüber bleibt root-only — dort liegen update_all.sh und der
 * Vendor-Baum, die der Cron-Job als root ausführt.
 */
function configWritable(): bool
{
    return file_exists(CONFIG_FILE)
        ? is_writable(CONFIG_FILE)
        : is_writable(dirname(CONFIG_FILE));
}

/**
 * Kann das Formular ICS-Dateien löschen?
 *
 * Zum Entfernen einer Datei braucht es Schreibrecht auf das VERZEICHNIS, nicht
 * auf die Datei selbst — die ICS-Dateien legt der Cron-Job als root an.
 * scripts/deploy.sh macht deshalb ics/ für die Webserver-Gruppe beschreibbar.
 */
function icsDirWritable(): bool
{
    return is_dir(ICS_DIR) && is_writable(ICS_DIR);
}

/**
 * Entfernt einen Eintrag aus teams.txt und löscht die zugehörige ICS-Datei.
 *
 * Aufgerufen wird das ausschließlich von add_team.php, also hinter
 * requireUser() und nach geprüftem CSRF-Token; index.php bindet common.php nur
 * für die Anzeige ein.
 *
 * Die Datei wird an Ort und Stelle neu geschrieben (öffnen, sperren, kürzen,
 * schreiben) statt über eine Temp-Datei umbenannt: Das Verzeichnis um
 * teams.txt gehört root, ein rename() scheiterte dort. LOCK_EX hält den
 * Schreibvorgang gegen ein parallel anhängendes Formular sauber.
 *
 * Kommentare, Leerzeilen und die Reihenfolge der übrigen Einträge bleiben
 * erhalten — teams.txt wird auch von Hand gepflegt.
 *
 * @return array{bool, string} [Erfolg, Meldung für den Benutzer]
 */
function deleteTeam(string $slug): array
{
    if (preg_match('/^[a-z0-9_-]+$/', $slug) !== 1) {
        return [false, 'Ungültiger Kurzname.'];
    }

    $removed = false;

    if (file_exists(CONFIG_FILE)) {
        $handle = @fopen(CONFIG_FILE, 'r+');
        if ($handle === false) {
            return [false, 'Konfigurationsdatei nicht beschreibbar (Serverkonfiguration prüfen).'];
        }

        if (!flock($handle, LOCK_EX)) {
            fclose($handle);
            return [false, 'Konfigurationsdatei ist gerade gesperrt, bitte erneut versuchen.'];
        }

        $content = stream_get_contents($handle);
        if ($content === false) {
            flock($handle, LOCK_UN);
            fclose($handle);
            return [false, 'Konfigurationsdatei nicht lesbar.'];
        }

        $kept = [];
        // Der letzte Eintrag von explode() ist bei abschließendem Zeilenumbruch
        // leer; implode() unten stellt den Umbruch dadurch wieder her.
        foreach (explode("\n", str_replace("\r\n", "\n", $content)) as $line) {
            [$candidate] = array_pad(explode(';', $line, 2), 2, '');
            if (trim($candidate) === $slug) {
                $removed = true;
                continue;
            }
            $kept[] = $line;
        }

        if ($removed) {
            $new = implode("\n", $kept);
            if (!ftruncate($handle, 0) || rewind($handle) === false
                || fwrite($handle, $new) === false || !fflush($handle)) {
                flock($handle, LOCK_UN);
                fclose($handle);
                return [false, 'Fehler beim Speichern der Konfigurationsdatei.'];
            }
        }

        flock($handle, LOCK_UN);
        fclose($handle);
    }

    // Auch ohne Eintrag in teams.txt aufräumen: Wird eine Zeile von Hand
    // entfernt, bleibt die ICS-Datei liegen und nginx liefert sie weiter aus.
    $icsPath  = ICS_DIR . '/' . $slug . '.ics';
    $icsThere = is_file($icsPath);
    $icsGone  = !$icsThere || @unlink($icsPath);

    // Die Statusdatei gehört zum Kalender und hat ohne ihn keinen Sinn. Ein
    // Fehlschlag ist hier kein Grund zur Warnung: sie wird nie ausgeliefert,
    // und der nächste Update-Lauf legt sie ohnehin nicht wieder an, wenn die
    // Zeile aus teams.txt verschwunden ist.
    $statePath = ICS_DIR . '/' . $slug . '.state';
    if (is_file($statePath)) {
        @unlink($statePath);
    }

    if (!$removed && !$icsThere) {
        return [false, "Kalender '$slug' war nicht (mehr) eingetragen."];
    }

    if (!$icsGone) {
        return [false, "Eintrag '$slug' entfernt, aber die Datei $slug.ics ließ sich nicht "
                     . 'löschen (Schreibrecht auf das ICS-Verzeichnis fehlt). Sie wird weiter '
                     . 'ausgeliefert, bis sie von Hand entfernt wird.'];
    }

    return [true, "Kalender '$slug' gelöscht. Bereits eingerichtete Abos laufen ins Leere und "
                . 'müssen in der Kalender-App selbst entfernt werden.'];
}

/** Basis-URL dieses Dienstes, wie der Browser ihn gerade sieht. */
function baseHost(): string
{
    return (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
}

/**
 * Der vom Webserver authentifizierte Benutzer, oder null.
 *
 * Die Authentifizierung macht nginx (auth_basic, siehe nginx/fussballcal.conf);
 * PHP bekommt den Namen ausschließlich über den fastcgi_param REMOTE_USER, den
 * der vhost in der geschützten location setzt. Ein HTTP-Header kann das nicht
 * fälschen: Header landen in PHP als HTTP_*, nicht als REMOTE_USER.
 * PHP_AUTH_USER greift zusätzlich, falls jemand den Authorization-Header
 * durchreicht (Apache, php -S, andere Setups).
 */
function currentUser(): ?string
{
    foreach (['REMOTE_USER', 'REDIRECT_REMOTE_USER', 'PHP_AUTH_USER'] as $key) {
        $value = trim((string)($_SERVER[$key] ?? ''));
        if ($value !== '') {
            return $value;
        }
    }

    return null;
}

/**
 * Bricht mit einer Erklärung ab, wenn die Seite ohne Authentifizierung
 * erreichbar ist.
 *
 * Absichtlich "fail closed": Wer den vhost selbst pflegt (deploy.sh --no-nginx)
 * oder einen anderen Webserver benutzt, soll eine deutliche Fehlermeldung
 * sehen — nicht ein offenes Formular, in das jeder eintragen kann.
 */
function requireUser(): string
{
    $user = currentUser();
    if ($user !== null) {
        return $user;
    }

    http_response_code(500);
    header('Content-Type: text/html; charset=utf-8');
    echo "<!DOCTYPE html>\n<html lang=\"de\"><head><meta charset=\"utf-8\">"
       . '<title>Konfigurationsfehler</title></head><body>'
       . '<h1>Nicht authentifiziert</h1>'
       . '<p>Diese Seite wird nur mit vorgeschalteter Authentifizierung ausgeliefert, '
       . 'der Webserver hat aber keinen Benutzer übergeben.</p>'
       . '<p>In <code>nginx/fussballcal.conf</code> muss die location für '
       . '<code>/add_team.php</code> <code>auth_basic</code> aktivieren und '
       . '<code>fastcgi_param REMOTE_USER $remote_user;</code> setzen. '
       . 'Zugangsdaten legt <code>scripts/set_password.sh</code> an.</p>'
       . '<p><a href="/">Zur Kalenderübersicht</a></p>'
       . '</body></html>';
    exit;
}

/** Gemeinsames Stylesheet beider Seiten. */
function pageStyles(): string
{
    return <<<'CSS'
        body { font-family: sans-serif; max-width: 32rem; margin: 2rem auto; padding: 0 1rem; }
        label { display: block; margin-top: 1rem; }
        input { width: 100%; padding: 0.4rem; box-sizing: border-box; }
        button { margin-top: 1rem; padding: 0.5rem 1rem; }
        .message { margin-top: 1rem; padding: 0.75rem; border-radius: 4px; white-space: pre-wrap; }
        .ok { background: #e6f4ea; color: #1e4620; }
        .err { background: #fdecea; color: #611a15; }
        .hint { color: #444; font-size: 0.9rem; }
        h2 { margin-top: 2.5rem; }
        ul.calendars { list-style: none; padding: 0; }
        ul.calendars li { border-top: 1px solid #ddd; padding: 0.75rem 0; }
        .slug { font-weight: bold; }
        .status { color: #666; font-size: 0.85rem; }
        .badge { font-size: 0.75rem; padding: 0.1rem 0.4rem; border-radius: 3px;
                 border: 1px solid transparent; white-space: nowrap; cursor: help; }
        .badge.laeuft  { background: #e6f4ea; color: #1e4620; border-color: #b7dfc2; }
        .badge.endet   { background: #fff4e5; color: #6b4500; border-color: #e6cfa8; }
        .badge.beendet { background: #f2f2f2; color: #444;    border-color: #ddd; }
        .badge.wartet  { background: #eaf1fb; color: #1c3f6e; border-color: #bcd0ea; }
        details.archiv { margin-top: 1.5rem; }
        details.archiv > summary { cursor: pointer; color: #444; font-size: 0.9rem;
                                   padding: 0.4rem 0; }
        details.archiv > ul.calendars { margin-top: 0.5rem; }
        .nav { margin-top: 2.5rem; border-top: 1px solid #ddd; padding-top: 1rem;
               color: #444; font-size: 0.9rem; }
        form.delete { display: inline; }
        form.delete button { margin: 0 0 0 0.5rem; padding: 0.1rem 0.5rem;
                             font-size: 0.85rem; color: #611a15; border: 1px solid #d9b0ac;
                             background: #fdecea; border-radius: 3px; cursor: pointer; }
        code { background: #f2f2f2; padding: 0.1rem 0.3rem; border-radius: 3px;
               font-size: 0.85rem; word-break: break-all; }
CSS;
}

/**
 * Ein Eintrag der Kalenderliste.
 *
 * Ausgelagert, weil ihn zwei Listen brauchen: die Übersicht der laufenden
 * Kalender und das Archiv darunter. Beide sehen gleich aus — der Unterschied
 * liegt allein darin, wo sie stehen.
 *
 * @param array{slug: string, url: string, exists: bool, mtime: ?int,
 *              state: array<string, string>} $team
 */
function renderCalendarEntry(array $team, string $host, ?string $csrf): void
{
    $webcal = 'webcal://' . $host . '/ics/' . $team['slug'] . '.ics';
    $https  = 'https://' . $host . '/ics/' . $team['slug'] . '.ics';
    $badge  = seasonBadge($team['state']);
    ?>
    <li>
        <span class="slug"><?= htmlspecialchars($team['slug']) ?></span>
        <?php if ($badge !== null): ?>
            <span class="badge <?= $badge[0] ?>" title="<?= htmlspecialchars($badge[2]) ?>"><?= htmlspecialchars($badge[1]) ?></span>
        <?php endif; ?>
        &mdash; <a href="<?= htmlspecialchars($webcal) ?>">Abonnieren</a>
        <?php if ($csrf !== null): ?>
            <?php // Löschen ist destruktiv: nur per POST, mit CSRF-Token und
                  // einer Rückfrage im Browser. ?>
            <form method="post" action="/add_team.php" class="delete"
                  onsubmit="return confirm('Kalender &quot;<?= htmlspecialchars($team['slug'], ENT_QUOTES) ?>&quot; wirklich löschen?');">
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf) ?>">
                <input type="hidden" name="slug" value="<?= htmlspecialchars($team['slug']) ?>">
                <button type="submit">Löschen</button>
            </form>
        <?php endif; ?>
        <br>
        <code><?= htmlspecialchars($https) ?></code><br>
        <span class="status">
            <?php if ($team['mtime'] !== null): ?>
                zuletzt aktualisiert: <?= htmlspecialchars(date('d.m.Y H:i', $team['mtime'])) ?>
            <?php elseif (($team['state']['status'] ?? '') === 'KEINE_SPIELE_MEHR_ERWARTET'): ?>
                <?php // Statusdatei ohne ICS: die Saison war schon vorbei, als der
                      // Eintrag angelegt wurde. Ein Kalender entsteht hier nicht mehr. ?>
                kein Kalender &ndash; für diese Saison liefert fussball.de keine Spiele
            <?php else: ?>
                wird beim nächsten Update erzeugt
            <?php endif; ?>
            <?php // Nur fussball.de verlinken – teams.txt kann von Hand
                  // gepflegt werden, ein "javascript:"-Link wäre sonst XSS. ?>
            <?php if (str_starts_with($team['url'], 'https://www.fussball.de/')): ?>
                &middot; <a href="<?= htmlspecialchars($team['url']) ?>">Quelle auf fussball.de</a>
            <?php endif; ?>
        </span>
    </li>
    <?php
}

/**
 * Liste aller Kalender mit Abo-Link und Stand der letzten Aktualisierung.
 *
 * Kalender endgültig abgeschlossener Saisons stehen darunter in einem
 * zugeklappten Archiv (siehe isArchived()). Grund ist der Saisonwechsel: Zur
 * neuen Saison kommt pro Mannschaft ein neuer Eintrag dazu, der alte bleibt
 * stehen — so empfiehlt es der README, und so bleibt der abonnierte Spielplan
 * erhalten. Ohne Archiv wüchse die Übersicht damit jede Saison um die volle
 * Mannschaftszahl, ausgerechnet auf der Seite, auf der jemand ein Abo *sucht*.
 *
 * Bewusst <details> statt JavaScript: die Seite kommt sonst auch ohne aus, und
 * der Browser kann das von sich aus. Die Zahl gehört in die Zusammenfassung —
 * sonst sucht jemand einen Kalender, der da ist, und findet ihn nicht.
 *
 * Mit $csrf bekommt jeder Eintrag zusätzlich einen Löschen-Knopf. Das Token
 * ist bewusst der Schalter dafür: Nur add_team.php hat eins (die Seite hinter
 * der Anmeldung, die den POST auch verarbeitet), die öffentliche index.php
 * ruft ohne auf und zeigt damit gar keine Knöpfe. Das Archiv ist auch dort
 * zugeklappt, aber vollständig — die Löschen-Knöpfe der alten Saisons sind
 * genau das, was beim Aufräumen gebraucht wird.
 *
 * @param list<array{slug: string, url: string, exists: bool, mtime: ?int,
 *                   state: array<string, string>}> $teams
 */
function renderCalendars(array $teams, string $host, ?string $csrf = null): void
{
    if ($teams === []) {
        echo '<p class="hint">Noch keine Teams eingetragen.</p>';
        return;
    }

    [$current, $archived] = splitArchived($teams);
    ?>
    <p class="hint">Auf <em>Abonnieren</em> klicken (öffnet die Kalender-App), oder die
       Adresse darunter kopieren und im Kalenderprogramm als Abo-URL einfügen.
       <?php if ($csrf !== null): ?>
           <em>Löschen</em> entfernt den Eintrag und die ICS-Datei vom Server; bereits
           eingerichtete Abos müssen zusätzlich in der Kalender-App entfernt werden.
       <?php endif; ?></p>
    <?php if ($csrf !== null && !icsDirWritable()): ?>
        <p class="hint">Hinweis: Das ICS-Verzeichnis ist für den Webserver nicht
           beschreibbar — beim Löschen bleibt die <code>.ics</code>-Datei liegen.
           <code>scripts/deploy.sh</code> erneut ausführen.</p>
    <?php endif; ?>
    <?php if ($current === []): ?>
        <p class="hint">Zurzeit läuft kein Kalender &mdash; alle eingetragenen Saisons
           sind abgeschlossen und stehen im Archiv.</p>
    <?php else: ?>
        <ul class="calendars">
        <?php foreach ($current as $team): ?>
            <?php renderCalendarEntry($team, $host, $csrf); ?>
        <?php endforeach; ?>
        </ul>
    <?php endif; ?>
    <?php if ($archived !== []): ?>
        <details class="archiv">
            <summary>Archiv: <?= count($archived) ?> beendete<?= count($archived) === 1 ? 'r' : '' ?> Kalender</summary>
            <p class="hint">Für diese Mannschaften ist die Saison abgeschlossen: das
               Saisonfenster ist abgelaufen, es kommen keine Spiele mehr dazu. Die
               Adressen bleiben gültig und die Kalender ändern sich nicht mehr &mdash;
               ein bestehendes Abo kann als Archiv der Saison stehen bleiben.</p>
            <ul class="calendars">
            <?php foreach ($archived as $team): ?>
                <?php renderCalendarEntry($team, $host, $csrf); ?>
            <?php endforeach; ?>
            </ul>
        </details>
    <?php endif; ?>
    <?php
}
