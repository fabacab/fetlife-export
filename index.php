<?php
/**
 * Oh, let's be careful with this one. :)
 */
require_once(dirname(__FILE__) . '/lib/FetLife.php');

$username = $_REQUEST['username'];
$password = $_REQUEST['password'];
$disallow_robots = (int)$_REQUEST['disallow_robots'];

$export_dir = $username . @date('-Y-m-d');
$zip_dir = dirname(basename(__FILE__)) . "/$export_dir";
$zip_url = dirname($_SERVER['PHP_SELF']) . "$export_dir.zip";

if ($username && (int)$_REQUEST['download_archive']) {
    exec(escapeshellcmd('zip -r ' . escapeshellarg($zip_dir) . '.zip ' . escapeshellarg($zip_dir)));
    header('Content-Type: application/zip');
    header('Content-Length: ' . filesize("$zip_dir.zip"));
    header("Content-Location: $zip_url");
    header("Content-Disposition: attachment; filename=\"$export_dir.zip\"");
    readfile("$zip_dir.zip");
    ob_end_flush();
    ob_flush();
    flush();
}
if ($username && $password && (int)$_REQUEST['delete_archive']) {
    $fetlife = new FetLifeUser($username, $password);
    if ($fetlife->logIn()) {
        // If a user wants to delete their archive from this server, delete ALL archives.
        exec(escapeshellcmd('rm -rf ' . escapeshellarg(substr($export_dir, 0, -11))) . '*', $output);
        exec(escayepeshellcmd('rm -f ' . escapeshellarg("$zip_dir.zip")), $output);
    }
    header("Location: {$SERVER_['PHP_SELF']}");
    exit(0);
}

// TODO: Make this work regardless of the current position of this script.
//       Right now, it only functions correctly if this file is placed in
//       the DOCUMENT_ROOT.
$robotstxt = realpath(dirname(basename($_SERVER['SCRIPT_NAME']))) . '/robots.txt';
define('FLEXPORT_ROBOTS_TXT', $robotstxt);

if (!file_exists(FLEXPORT_ROBOTS_TXT)) {
    if ($fh = fopen(FLEXPORT_ROBOTS_TXT, 'w')) {
        fwrite($fh, "User-Agent: *\n");
        fclose($fh);
    } else {
        die("Couldn't create " . FLEXPORT_ROBOTS_TXT . ". Make sure directory permissions are set appropriately?");
    }
}
?><!DOCTYPE html>
<html lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>FetLife Exporter</title>
</head>
<body>
    <h1>FetLife Exporter</h1>
    <p>This tool lets you export your FetLife history.</p>
    <form action="<?php print $_SERVER['PHP_SELF']?>" method="post">
        <fieldset>
            <legend>FetLife connection details</legend>
            <label for="username">Username:</label>
            <input name="username" id="username" value="username" />
            <label for="password">Password:</label>
            <input type="password" name="password" id="password" value="password" />
        </fieldset>
        <fieldset<?php if ('/' !== dirname($_SERVER['REQUEST_URI'])) : print ' style="display:none"' ; endif;;?>>
            <legend>Export options</legend>
            <label for="disallow_robots">Ask search engines not to index your exported archive:</label>
            <input type="checkbox" name="disallow_robots" id="disallow_robots" value="1" />
        </fieldset>
        <input type="submit" />
    </form>
<?php
// Show google a directory listing so it can find exports.
if (is_google()) { ?>
    <p>Exported directories on this server:</p>
<?php
    $globbed_dirs = glob("*-20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]", GLOB_ONLYDIR);
    if ($globbed_dirs) {
        print '<ul id="exported-directories">';
        foreach ($globbed_dirs as $globbed_dir_name) {
?>
        <li><a href="<?php printHTMLSafe($globbed_dir_name);?>/"><?php printHTMLSafe($globbed_dir_name);?></a></li>
<?php
        }
        print '</ul>';
    }
}

if (empty($username) || empty($password)) {
    die("</body></html><!-- No username or password found. -->");
}

$cmd = 'fetlife-export.pl';
$cmd_safe = escapeshellcmd("./$cmd " . escapeshellarg($username) . ' ' . escapeshellarg($export_dir));

$descriptorspec = array(
    0 => array("pipe", "r"), // stdin is a pipe that the child will read from
    1 => array("pipe", "w"), // stdout is a pipe that the child will write to
    2 => array("pipe", "w")  // stderr is a pipe that the child will write to
);
$pipes = array();
$ph = proc_open($cmd_safe, $descriptorspec, $pipes, './');
if (!is_resource($ph)) {
    die("Error executing $cmd_safe");
}

if ('Password: ' === stream_get_contents($pipes[1], 10)) {
    fwrite($pipes[0], "$password\n");
}

while ($line = stream_get_line($pipes[1], 1024)) {
//    var_dump(str_replace("\n", '\n', str_replace("\r", '\r', $line)));

    if (empty($line)) { continue; }

    // Extract info from output.
    $matches = array();
    if (preg_match('/userID: ([0-9]+)/', $line, $matches)) {
        $id = $matches[1];
    }
    if (preg_match('/([0-9]+) conversations? found./', $line, $matches)) {
        $num_conversations = $matches[1];
    }
    if (preg_match('/([0-9]+) wall-to-walls? found./', $line, $matches)) {
        $num_wall_to_walls = $matches[1];
    }
    if (preg_match('/([0-9]+) status(?:es)? found./', $line, $matches)) {
        $num_statuses = $matches[1];
    }
    if (preg_match('/([0-9]+) pictures? found./', $line, $matches)) {
        $num_pics = $matches[1];
    }
    if (preg_match('/([0-9]+) writings? found./', $line, $matches)) {
        $num_writings = $matches[1];
    }
    if (preg_match('/([0-9]+) group threads? found./', $line, $matches)) {
        $num_group_threads = $matches[1];
    }
}

foreach ($pipes as $pipe) {
    fclose($pipe);
}
proc_close($ph);

if ($disallow_robots && is_dir($export_dir)) {
    if (disallowRobots($export_dir)) {
?>
    <p>We've requested that search engines <em>not</em> index your FetLife export. (This is not a guarantee they'll behave!)</p>
<?php
    } else {
?>
    <p>You requested that search engines <em>not</em> index your FetLife export, but there was an error handling this request. Please contact the site administrator for assistance.</p>
<?php
    }
}
?>
    <p>Done exporting user ID <?php printHTMLSafe($id);?>. Found:</p>
    <ul>
        <li><?php printHTMLSafe($num_conversations);?> conversations,</li>
        <li><?php printHTMLSafe($num_wall_to_walls);?> wall-to-walls,</li>
        <li><?php printHTMLSafe($num_statuses);?> statuses,</li>
        <li><?php printHTMLSafe($num_pics);?> pictures,</li>
        <li><?php printHTMLSafe($num_writings);?> writings,</li>
        <li><?php printHTMLSafe($num_group_threads);?> group threads.</li>
    </ul>
    <p><a href="<?php printHTMLSafe($export_dir);?>/fetlife/" target="_blank">Browse <?php printHTMLSafe($username);?></a>. Or:</p>
    <form action="<?php print $_SERVER['PHP_SELF']?>" method="post">
        <input type="hidden" name="username" id="download_username" value="<?php printHTMLSafe($username);?>" />
        <input type="hidden" name="password" id="download_password" value="<?php printHTMLSafe($password);?>" />
        <input type="hidden" name="download_archive" id="download_archive" value="1" />
        <input type="submit" value="Download my export as a ZIP archive." />
        <fieldset>
            <legend>Archive options</legend>
            <label for="delete_archive">Don't save a copy of my export after I download it:</label>
            <input type="checkbox" name="delete_archive" id="delete_archive" value="1" />
        </fieldset>
    </form>
</body>
</html>
<?php
function printHTMLSafe ($str) {
    print htmlentities($str, ENT_QUOTES, 'UTF-8');
}

function disallowRobots ($dir) {
    if (!$fh = fopen(FLEXPORT_ROBOTS_TXT, 'r+')) {
        return false;
    }
    // Search for pre-existing "Disallow" directive, return true if found.
    while (($line = fgets($fh)) !== false) {
        if (preg_match("/Disallow: $dir/", $line)) {
            fclose($fh);
            return true;
        }
    }
    $ret = fwrite($fh, "Disallow: $dir/\n");
    fclose($fh);
    return $ret;
}

function is_google () {
    if (strpos($_SERVER['HTTP_USER_AGENT'], 'Googlebot')) {
        return true;
    } else {
        return false;
    }
}
?>
