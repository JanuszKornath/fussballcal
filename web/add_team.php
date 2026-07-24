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

const CONFIG_FILE = '/srv/spielplanoffline/teams.txt';
const MAX_TEAMS = 200; // simple Obergrenze gegen Missbrauch

function respond(string $message, bool $ok): void
{
    http_response_code($ok ? 200 : 400);
    echo $message;
    exit;
}

$slug = '';
$url = '';
$message = '';
$success = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $rawSlug = trim((string)($_POST['slug'] ?? ''));
    $rawUrl  = trim((string)($_POST['url'] ?? ''));

    $slug = strtolower(preg_replace('/[^a-zA-Z0-9_-]/', '', $rawSlug) ?? '');
    $url  = filter_var($rawUrl, FILTER_VALIDATE_URL) ?: '';

    if ($slug === '' || $url === '') {
        $message = 'Bitte einen gültigen Kurznamen und Link angeben.';
    } elseif (!str_starts_with($url, 'https://www.fussball.de/')) {
        $message = 'Nur Links von https://www.fussball.de/ werden akzeptiert.';
    } elseif (!is_writable(dirname(CONFIG_FILE))) {
        $message = 'Konfigurationsverzeichnis nicht beschreibbar (Serverkonfiguration prüfen).';
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
                $message = "Hinzugefügt. Nach dem nächsten Update verfügbar unter:\n"
                          . "webcal://" . $_SERVER['HTTP_HOST'] . "/ics/" . $slug . ".ics";
            } else {
                $message = 'Fehler beim Speichern.';
            }
        }
    }
}
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
    </style>
</head>
<body>
    <h1>Fussball-Kalender hinzufügen</h1>
    <p>Link zu einer Mannschaft oder einem Verein auf fussball.de eintragen.
       Der Kalender wird beim nächsten automatischen Update erzeugt.</p>

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
</body>
</html>
