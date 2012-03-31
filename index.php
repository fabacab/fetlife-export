<?php
/**
 * Oh, let's be careful with this one. :)
 */

//ob_implicit_flush(TRUE);
//ob_end_flush();

$username = $_GET['username'];
$password = $_GET['password'];

$cmd_safe = escapeshellcmd('./fetlife-export.pl ' . escapeshellarg($username) . ' ' . escapeshellarg($username));

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

//stream_set_blocking($pipes[0], 0);
//stream_set_blocking($pipes[1], 0);
//stream_set_blocking($pipes[2], 0);

if ('Password: ' === stream_get_contents($pipes[1], 10)) {
    echo "We saw a password prompt";
    echo "Sending '$password\\n'";
    fwrite($pipes[0], "$password\n");
}

$read = array($pipes[1], $pipes[2]);
$write = array($pipes[0]);
$except = NULL;
while (!false === stream_select($read, $write, $except, 1)) {
    foreach ($read as $stream) {
        if ($pipes[1] === $stream) {
            print "Stream STDOUT";
            print stream_get_contents($stream, 1);
            var_dump(stream_get_meta_data($stream));
        } elseif ($pipes[2] === $stream) {
            print "Stream STDERR";
            print stream_get_contents($stream, 1);
            var_dump(stream_get_meta_data($stream));
        } else {
            print "Some other stream?";
            var_dump(stream_get_meta_data($stream));
        }
    }
}

//while (!feof($pipes[1])) {
//    print stream_get_contents($pipes[1], 1);
//}

fclose($pipes[0]);
fclose($pipes[1]);
proc_close($ph);
?>
