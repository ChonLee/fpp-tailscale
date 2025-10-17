<?php
$script_path = __DIR__ . '/tailscale_manager.sh';

if (isset($_GET['action'])) {
    $action = $_GET['action'];
    switch($action){
        case "install":
        case "up":
        case "down":
            echo shell_exec("bash $script_path $action 2>&1");
            break;
        case "auth":
            $link = shell_exec("bash $script_path auth 2>/dev/null");
            echo $link ? $link : '';
            break;
        case "status":
            header('Content-Type: application/json');
            echo shell_exec("bash $script_path status 2>/dev/null");
            break;
    }
    exit;
}
?>

<!DOCTYPE html>
<html>
<head>
    <title>FPP Tailscale</title>
    <link rel="stylesheet" href="plugin.css">
    <script src="plugin.js"></script>
</head>
<body>
    <h2>FPP Tailscale Manager</h2>

    <button onclick="runAction('install')">Install Tailscale</button>
    <button onclick="runAction('up')">Tailscale Up</button>
    <button onclick="runAction('down')">Tailscale Down</button>

    <h3>Installation Log</h3>
    <pre id="log"></pre>

    <h3>Authorization</h3>
    <div id="authLink"></div>

    <h3>Status</h3>
    <pre id="status"></pre>

    <script>
        // Poll for status every 5 seconds
        setInterval(updateStatus, 5000);
        updateStatus();
    </script>
</body>
</html>
