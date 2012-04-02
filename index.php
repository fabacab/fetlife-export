<?php
/**
 * Oh, let's be careful with this one. :)
 */

$username = $_GET['username'];
$password = $_GET['password'];

$cmd = 'fetlife-export.pl';
$export_dir = $username . @date('-Y-m-d');

?><!DOCTYPE html>
<html lang="en">
<head>
<title>FetLife Exporter</title>
</head>
<body>
    <h1>FetLife Exporter</h1>
    <p>This tool lets you export your FetLife history.</p>
    <form action="<?php print $_SERVER['PHP_SELF']?>">
        <fieldset>
            <legend>FetLife connection details</legend>
            <label for="username">Username:</label>
            <input name="username" id="username" value="username" />
            <label for="password">Password:</label>
            <input type="password" name="password" id="password" value="password" />
        </fieldset>
        <input type="submit" />
    </form>
<?php

if (empty($username) || empty($password)) {
    die("</body></html><!-- No username or password found. -->");
}

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
?>
    <p>Done exporting user ID <?php print $id;?>. Found:</p>
    <ul>
        <li><?php printHTMLSafe($num_conversations);?> conversations,</li>
        <li><?php printHTMLSafe($num_wall_to_walls);?> wall-to-walls,</li>
        <li><?php printHTMLSafe($num_statuses);?> statuses,</li>
        <li><?php printHTMLSafe($num_pics);?> pictures,</li>
        <li><?php printHTMLSafe($num_writings);?> writings,</li>
        <li><?php printHTMLSafe($num_group_threads);?> group threads.</li>
    </ul>
    <p><a href="<?php printHTMLSafe($export_dir);?>/fetlife/">Browse <?php printHTMLSafe($username);?></a>.</p>
<?php
foreach ($pipes as $pipe) {
    fclose($pipe);
}
proc_close($ph);
?>
</body>
</html>
<?
function printHTMLSafe ($str) {
    print htmlentities($str, ENT_QUOTES, 'UTF-8');
}
?>
