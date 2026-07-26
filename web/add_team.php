<?php
/**
 * add_team.php
 *
 * Einfaches Formular, um Fussball.de-Links zur teams.txt hinzuzufügen.
 * Läuft der Cron-Job danach (siehe update_all.sh), wird automatisch
 * eine ICS-Datei erzeugt.
 *
 * SICHERHEIT:
 * - Nur fussball.de-URLs werden akzeptiert.
 * - Slug wird auf [a-z0-9_-] beschränkt (Whitelist, kein Escaping nötig,
 *   da ungültige Zeichen komplett verworfen werden).
 * - Die URL wird NIE in einen Shell-Befehl eingebaut (das übernimmt
 *   ausschließlich update_all.sh mit escapten/validierten Werten).
 * - Für den Produktivbetrieb: zusätzlich Auth/Captcha/Rate-Limiting
 *   ergänzen, sonst kann jeder beliebig viele Einträge anlegen.
 */

declare(strict_types=1);

// Pfade dieser Installation. scripts/deploy.sh legt config.php neben dieses
// Skript und trägt dort die tatsächlich benutzten Pfade ein — sonst zeigte das
// Formular bei einem verschobenen Rollout weiter auf /srv/spielplanoffline und
// schriebe in eine Datei, die der Cron-Job gar nicht liest. Ohne die Datei
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
 * Kann dieses Formular einen Eintrag anhängen?
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

$slug = '';
$url = '';
$message = '';
$success = false;
$host = baseHost();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $rawSlug = trim((string)($_POST['slug'] ?? ''));
    $rawUrl  = trim((string)($_POST['url'] ?? ''));

    $slug = strtolower(preg_replace('/[^a-zA-Z0-9_-]/', '', $rawSlug) ?? '');
    $url  = filter_var($rawUrl, FILTER_VALIDATE_URL) ?: '';

    if ($slug === '' || $url === '') {
        $message = 'Bitte einen gültigen Kurznamen und Link angeben.';
    } elseif (!str_starts_with($url, 'https://www.fussball.de/')) {
        $message = 'Nur Links von https://www.fussball.de/ werden akzeptiert.';
    } elseif (!configWritable()) {
        $message = 'Konfigurationsdatei nicht beschreibbar (Serverkonfiguration prüfen).';
    } else {
        $existing = file_exists(CONFIG_FILE) ? file(CONFIG_FILE, FILE_IGNORE_NEW_LINES) : [];
        $existing = $existing === false ? [] : $existing;

        $slugTaken = false;
        foreach ($existing as $line) {
            if (str_starts_with($line, $slug . ';')) {
                $slugTaken = true;
                break;
            }
        }

        if (count($existing) >= MAX_TEAMS) {
            $message = 'Maximale Anzahl an Teams erreicht.';
        } elseif ($slugTaken) {
            $message = "Kurzname '$slug' ist bereits vergeben.";
        } else {
            $line = $slug . ';' . $url . "\n";
            if (file_put_contents(CONFIG_FILE, $line, FILE_APPEND | LOCK_EX) !== false) {
                $success = true;
                $message = "Hinzugefügt. Nach dem nächsten Update (alle 6 Stunden) verfügbar unter:\n"
                          . "webcal://" . baseHost() . "/ics/" . $slug . ".ics";
            } else {
                $message = 'Fehler beim Speichern.';
            }
        }
    }
}

// Erst nach dem POST einlesen, damit ein gerade hinzugefügtes Team sofort
// in der Liste auftaucht.
$teams = readTeams();
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <title>Fussball-Kalender hinzufügen</title>
    <style>
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
        code { background: #f2f2f2; padding: 0.1rem 0.3rem; border-radius: 3px;
               font-size: 0.85rem; word-break: break-all; }
    </style>
</head>
<body>
    <h1>Fussball-Kalender hinzufügen</h1>
    <p>Link zu einer Mannschaft oder einem Verein auf fussball.de eintragen.
       Der Kalender wird beim nächsten automatischen Update erzeugt.</p>
    <p class="hint">So kommst du an den Link: auf
       <a href="https://www.fussball.de/">fussball.de</a> die Mannschaft oder den
       Verein suchen, deren Seite öffnen und die Adresse aus der Adresszeile des
       Browsers kopieren (<code>.../mannschaft/…</code> oder
       <code>.../verein/…</code>).</p>

    <form method="post">
        <label>Fussball.de-Link
            <input type="url" name="url" required placeholder="https://www.fussball.de/mannschaft/..." value="<?= htmlspecialchars($url) ?>">
        </label>
        <label>Kurzname (für den Dateinamen, z.B. tsv-musterstadt-1)
            <input type="text" name="slug" required pattern="[a-zA-Z0-9_-]+" value="<?= htmlspecialchars($slug) ?>">
        </label>
        <button type="submit">Hinzufügen</button>
    </form>

    <?php if ($message !== ''): ?>
        <div class="message <?= $success ? 'ok' : 'err' ?>"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>

    <h2>Vorhandene Kalender</h2>
    <?php if ($teams === []): ?>
        <p class="hint">Noch keine Teams eingetragen.</p>
    <?php else: ?>
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
    <?php endif; ?>
</body>
</html>
