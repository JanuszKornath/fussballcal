<?php
/**
 * add_team.php
 *
 * Formular, um Fussball.de-Links zur teams.txt hinzuzufügen. Läuft der
 * Cron-Job danach (siehe update_all.sh), wird automatisch eine ICS-Datei
 * erzeugt. Die öffentliche Übersicht der fertigen Kalender ist index.php.
 *
 * SICHERHEIT:
 * - Diese Seite liegt hinter der Basic-Auth des vhosts (nginx: auth_basic,
 *   Zugangsdaten via scripts/set_password.sh). Ohne authentifizierten
 *   Benutzer bricht requireUser() ab, statt ein offenes Formular zu zeigen.
 * - Nur fussball.de-URLs werden akzeptiert.
 * - Slug wird auf [a-z0-9_-] beschränkt (Whitelist, kein Escaping nötig,
 *   da ungültige Zeichen komplett verworfen werden).
 * - Die URL wird NIE in einen Shell-Befehl eingebaut (das übernimmt
 *   ausschließlich update_all.sh mit escapten/validierten Werten).
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

// Vor jeder Ausgabe und vor jeder Verarbeitung: nur authentifiziert weiter.
$user = requireUser();

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
                          . "webcal://" . $host . "/ics/" . $slug . ".ics";
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
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Fussball-Kalender hinzufügen</title>
    <style>
<?= pageStyles() ?>
    </style>
</head>
<body>
    <h1>Fussball-Kalender hinzufügen</h1>
    <p class="hint">Angemeldet als <strong><?= htmlspecialchars($user) ?></strong>.</p>
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
    <?php renderCalendars($teams, $host); ?>

    <p class="nav">Die öffentliche Übersicht zum Weitergeben:
       <a href="/">Startseite</a> — dort steht dieselbe Liste ohne Anmeldung
       und ohne dieses Formular.</p>
</body>
</html>
