<?php
/**
 * add_team.php
 *
 * Einfaches Formular, um Fussball.de-Links zur teams.txt hinzuzufügen und
 * eingetragene Kalender wieder zu löschen. Läuft der Cron-Job danach (siehe
 * update_all.sh), wird automatisch eine ICS-Datei erzeugt.
 *
 * SICHERHEIT:
 * - Nur fussball.de-URLs werden akzeptiert.
 * - Slug wird auf [a-z0-9_-] beschränkt (Whitelist, kein Escaping nötig,
 *   da ungültige Zeichen komplett verworfen werden). Beim Löschen ist das
 *   zugleich der Schutz gegen Pfad-Traversal: aus dem Slug wird ein
 *   Dateiname, "../" o.ä. kommt gar nicht erst durch.
 * - Die URL wird NIE in einen Shell-Befehl eingebaut (das übernimmt
 *   ausschließlich update_all.sh mit escapten/validierten Werten).
 * - Löschen (destruktiv) läuft nur per POST und nur mit gültigem
 *   CSRF-Token, damit keine fremde Seite Kalender im Vorbeigehen entfernen
 *   kann.
 * - Für den Produktivbetrieb: zusätzlich Auth/Captcha/Rate-Limiting
 *   ergänzen, sonst kann jeder beliebig viele Einträge anlegen und löschen.
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

/**
 * Kann dieses Formular ICS-Dateien löschen?
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

// CSRF-Token in der Session. Ohne Login ist das kein Zugriffsschutz, es
// verhindert aber, dass eine fremde Seite den Browser eines Besuchers ein
// Löschen absenden lässt.
session_start();
if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(16));
}
$csrf = $_SESSION['csrf'];

$slug = '';
$url = '';
$message = '';
$success = false;
$host = baseHost();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
    // Typischer Fall: die Seite lag lange offen und die Session ist abgelaufen.
    $message = 'Sitzung abgelaufen — bitte die Seite neu laden und noch einmal versuchen.';
} elseif (($_POST['action'] ?? '') === 'delete') {
    $delSlug = strtolower(preg_replace('/[^a-zA-Z0-9_-]/', '', trim((string)($_POST['slug'] ?? ''))) ?? '');

    if ($delSlug === '') {
        $message = 'Kein Kalender zum Löschen angegeben.';
    } else {
        [$success, $message] = deleteTeam($delSlug);
    }
} elseif ($_SERVER['REQUEST_METHOD'] === 'POST') {
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
        form.delete { display: inline; }
        form.delete button { margin: 0 0 0 0.5rem; padding: 0.1rem 0.5rem;
                             font-size: 0.85rem; color: #611a15; border: 1px solid #d9b0ac;
                             background: #fdecea; border-radius: 3px; cursor: pointer; }
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
        <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf) ?>">
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
           Adresse darunter kopieren und im Kalenderprogramm als Abo-URL einfügen.
           <em>Löschen</em> entfernt den Eintrag und die ICS-Datei vom Server; bereits
           eingerichtete Abos müssen zusätzlich in der Kalender-App entfernt werden.</p>
        <?php if (!icsDirWritable()): ?>
            <p class="hint">Hinweis: Das ICS-Verzeichnis ist für den Webserver nicht
               beschreibbar — beim Löschen bleibt die <code>.ics</code>-Datei liegen.
               <code>scripts/deploy.sh</code> erneut ausführen.</p>
        <?php endif; ?>
        <ul class="calendars">
        <?php foreach ($teams as $team): ?>
            <?php
                $webcal = 'webcal://' . $host . '/ics/' . $team['slug'] . '.ics';
                $https  = 'https://' . $host . '/ics/' . $team['slug'] . '.ics';
            ?>
            <li>
                <span class="slug"><?= htmlspecialchars($team['slug']) ?></span>
                &mdash; <a href="<?= htmlspecialchars($webcal) ?>">Abonnieren</a>
                <?php // Löschen ist destruktiv: nur per POST, mit CSRF-Token und
                      // einer Rückfrage im Browser. ?>
                <form method="post" class="delete"
                      onsubmit="return confirm('Kalender &quot;<?= htmlspecialchars($team['slug'], ENT_QUOTES) ?>&quot; wirklich löschen?');">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf) ?>">
                    <input type="hidden" name="slug" value="<?= htmlspecialchars($team['slug']) ?>">
                    <button type="submit">Löschen</button>
                </form><br>
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
