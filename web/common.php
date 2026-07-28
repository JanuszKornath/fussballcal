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
 * Liest teams.txt nach der gleichen Konvention wie update_all.sh
 * (Format "slug;url", Leerzeilen und #-Kommentare werden übersprungen) und
 * reichert jeden Eintrag mit dem Status der zugehörigen ICS-Datei an.
 *
 * @return list<array{slug: string, url: string, exists: bool, mtime: ?int}>
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
        .nav { margin-top: 2.5rem; border-top: 1px solid #ddd; padding-top: 1rem;
               color: #444; font-size: 0.9rem; }
        code { background: #f2f2f2; padding: 0.1rem 0.3rem; border-radius: 3px;
               font-size: 0.85rem; word-break: break-all; }
CSS;
}

/**
 * Liste aller Kalender mit Abo-Link und Stand der letzten Aktualisierung.
 *
 * @param list<array{slug: string, url: string, exists: bool, mtime: ?int}> $teams
 */
function renderCalendars(array $teams, string $host): void
{
    if ($teams === []) {
        echo '<p class="hint">Noch keine Teams eingetragen.</p>';
        return;
    }
    ?>
    <p class="hint">Auf <em>Abonnieren</em> klicken (öffnet die Kalender-App), oder die
       Adresse darunter kopieren und im Kalenderprogramm als Abo-URL einfügen.</p>
    <ul class="calendars">
    <?php foreach ($teams as $team): ?>
        <?php
            $webcal = 'webcal://' . $host . '/ics/' . $team['slug'] . '.ics';
            $https  = 'https://' . $host . '/ics/' . $team['slug'] . '.ics';
        ?>
        <li>
            <span class="slug"><?= htmlspecialchars($team['slug']) ?></span>
            &mdash; <a href="<?= htmlspecialchars($webcal) ?>">Abonnieren</a><br>
            <code><?= htmlspecialchars($https) ?></code><br>
            <span class="status">
                <?php if ($team['mtime'] !== null): ?>
                    zuletzt aktualisiert: <?= htmlspecialchars(date('d.m.Y H:i', $team['mtime'])) ?>
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
    <?php endforeach; ?>
    </ul>
    <?php
}
