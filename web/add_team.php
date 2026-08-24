<?php
/**
 * add_team.php
 *
 * Formular, um Fussball.de-Links zur teams.txt hinzuzufügen und eingetragene
 * Kalender wieder zu löschen. Läuft der Cron-Job danach (siehe update_all.sh),
 * wird automatisch eine ICS-Datei erzeugt. Die öffentliche Übersicht der
 * fertigen Kalender ist index.php — dort ohne Formular und ohne Löschen.
 *
 * SICHERHEIT:
 * - Diese Seite liegt hinter der Basic-Auth des vhosts (nginx: auth_basic,
 *   Zugangsdaten via scripts/set_password.sh). Ohne authentifizierten
 *   Benutzer bricht requireUser() ab, statt ein offenes Formular zu zeigen.
 *   Damit hängt auch das Löschen hinter der Anmeldung: index.php ruft
 *   renderCalendars() ohne Token auf und zeigt deshalb keine Knöpfe, und die
 *   Verarbeitung steckt ohnehin nur hier — hinter requireUser().
 * - Nur fussball.de-URLs werden akzeptiert.
 * - Slug wird auf [a-z0-9_-] beschränkt (Whitelist, kein Escaping nötig,
 *   da ungültige Zeichen komplett verworfen werden). Beim Löschen ist das
 *   zugleich der Schutz gegen Pfad-Traversal: aus dem Slug wird ein
 *   Dateiname, "../" o.ä. kommt gar nicht erst durch.
 * - Die URL wird NIE in einen Shell-Befehl eingebaut (das übernimmt
 *   ausschließlich update_all.sh mit escapten/validierten Werten).
 * - Löschen (destruktiv) läuft nur per POST und nur mit gültigem CSRF-Token.
 *   Basic-Auth allein reicht dafür nicht: Der Browser hängt die Zugangsdaten
 *   an jede Anfrage an diese Adresse, auch an eine, die eine fremde Seite
 *   auslöst.
 */

declare(strict_types=1);

require_once __DIR__ . '/common.php';

// Vor jeder Ausgabe und vor jeder Verarbeitung: nur authentifiziert weiter.
$user = requireUser();

// CSRF-Token in der Session, gegen Anfragen, die eine fremde Seite im Namen
// des angemeldeten Benutzers absendet.
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
                          . "webcal://" . $host . "/ics/" . $slug . ".ics";
            } else {
                $message = 'Fehler beim Speichern.';
            }
        }
    }
}

// Erst nach dem POST einlesen, damit ein gerade hinzugefügtes Team sofort in
// der Liste auftaucht und ein gerade gelöschtes daraus verschwindet.
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
    <p class="hint">Ein <em>Mannschafts</em>link gilt nur für eine Saison —
       fussball.de führt die Saison in der Adresse mit
       (<code>.../saison/2526/...</code>). Zur neuen Saison also den neuen Link
       eintragen, am besten unter einem eigenen Kurznamen (z.B.
       <code>tsv-musterstadt-1-2627</code>). Der alte Kalender bleibt dann als
       Archiv der vergangenen Saison stehen, und die Abonnenten müssen die neue
       Adresse abonnieren: ein bestehendes Abo wechselt nicht von selbst auf die
       neue Saison. Ein <em>Vereins</em>link ist nicht saisongebunden und läuft
       von selbst weiter.</p>
    <p class="hint">Stehenlassen kostet keinen Platz in der Übersicht: Sobald das
       Saisonfenster abgelaufen ist, rutscht der alte Eintrag unten in das
       zugeklappte <em>Archiv</em> — auf beiden Seiten, hier mitsamt seinem
       Löschen-Knopf.</p>
    <p class="hint">Sobald für eine Mannschaft kein Spiel mehr ansteht, wird der
       Kalender in der Übersicht als <em>vermutlich beendet</em> markiert und
       enthält einen entsprechenden Termin. Mit Gewissheit lässt sich das
       Saisonende nicht bestimmen — fussball.de nennt keines, und Nachhol- oder
       Pokalspiele können noch folgen. Der Kalender läuft dann einfach weiter.
       Genau deshalb wandert er in diesem Zustand noch <em>nicht</em> ins Archiv:
       dorthin kommt er erst, wenn zusätzlich das Saisonfenster abgelaufen ist
       und damit feststeht, dass nichts mehr nachkommt.</p>

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
    <?php // Mit Token: dieselbe Liste wie auf der Startseite, zusätzlich mit
          // Löschen-Knöpfen. ?>
    <?php renderCalendars($teams, $host, $csrf); ?>

    <p class="nav">Die öffentliche Übersicht zum Weitergeben:
       <a href="/">Startseite</a> — dort steht dieselbe Liste ohne Anmeldung
       und ohne dieses Formular.</p>
</body>
</html>
