<?php
/**
 * Oh, let's be careful with this one. :)
 */

$username = $_GET['username'];
$password = $_GET['password'];

$cmd = 'fetlife-export.pl';
$export_dir = $username . date('-Y-m-d');

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

print "Done exporting user ID $id!";
print "Found $num_conversations conversations, $num_wall_to_walls wall-to-walls, $num_statuses statuses, $num_pics pictures, $num_writings writings, and $num_group_threads group threads.";

$username_html_safe = htmlentities($username, ENT_QUOTES, 'UTF-8');
$export_dir_html_safe = htmlentities($export_dir, ENT_QUOTES, 'UTF-8');
print "<a href=\"$export_dir\">Browse $username_html_safe.</a>";

foreach ($pipes as $pipe) {
    fclose($pipe);
}
proc_close($ph);
?>
