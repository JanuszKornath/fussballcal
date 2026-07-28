<?php
/**
 * index.php
 *
 * Öffentliche Startseite: listet alle erzeugten Kalender mit Abo-Link auf.
 * Bewusst ohne Authentifizierung — die Kalender sollen ohne Login abonnierbar
 * sein. Eingetragen werden neue Mannschaften nur über add_team.php, das hinter
 * der Basic-Auth des vhosts liegt.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

$host  = baseHost();
$teams = readTeams();
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Fussball-Kalender</title>
    <style>
<?= pageStyles() ?>
    </style>
</head>
<body>
    <h1>Fussball-Kalender</h1>
    <p>Spielpläne von <a href="https://www.fussball.de/">fussball.de</a> als
       Kalender-Abo. Die Kalender werden automatisch alle sechs Stunden
       aktualisiert — einmal abonniert, bleibt der Spielplan von selbst
       aktuell.</p>

    <h2>Vorhandene Kalender</h2>
    <?php renderCalendars($teams, $host); ?>

    <p class="hint">Wichtig: die Datei nicht herunterladen und importieren —
       dann bleibt der Kalender auf dem Stand des Downloads. Nur ein
       <em>Abo</em> der Adresse aktualisiert sich selbst.</p>

    <p class="nav">Eine Mannschaft fehlt?
       <a href="/add_team.php">Neue Mannschaft eintragen</a> (nur mit Zugangsdaten).</p>
</body>
</html>
