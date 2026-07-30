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

    <p class="hint">Ebenfalls wichtig: <strong>die meisten Kalender gelten nur
       für eine Saison.</strong> fussball.de vergibt Mannschaftslinks pro
       Saison, ein Abo enthält deshalb nur die Spiele der Saison, für die es
       eingetragen wurde. Zur neuen Saison erscheint hier ein neuer Kalender mit
       neuer Adresse — die muss dann <em>zusätzlich abonniert</em> werden. Das
       alte Abo aktualisiert sich nicht mehr und kann in der Kalender-App
       entfernt werden. Kalender, die aus einem Vereinslink stammen, sind davon
       ausgenommen; sie sind oben als <em>nicht saisongebunden</em>
       gekennzeichnet und laufen von selbst weiter.</p>

    <p class="hint">Das Abzeichen hinter jedem Kalender sagt, woran er ist.
       <em>Vermutlich beendet</em> heißt: für diese Mannschaft steht kein Spiel
       mehr an. Ganz sicher ist das nie — fussball.de nennt kein Saisonende,
       und Nachhol- oder Pokalspiele können noch dazukommen. In beendeten
       Kalendern steht am Ende zusätzlich ein Termin mit demselben Hinweis,
       damit er auch in der Kalender-App auffällt.</p>

    <p class="nav">Eine Mannschaft fehlt?
       <a href="/add_team.php">Neue Mannschaft eintragen</a> (nur mit Zugangsdaten).</p>
</body>
</html>
