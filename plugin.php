<?php
$script_path = __DIR__ . '/tailscale_manager.sh';

// Handle AJAX actions
if (isset($_GET['action'])) {
    $action = $_GET['action'];
    switch($action){
        case "install":
        case "up":
        case "down":
            $output = shell_exec("sudo bash $script_path $action 2>&1");
            if (!$output) $output = "No output. Check sudo permissions and PATH.";
            echo $output;
            break;

        case "auth":
            $link = shell_exec("sudo bash $script_path auth 2>/dev/null");
            echo $link ? $link : '';
            break;

        case "status":
            header('Content-Type: application/json');
            echo shell_exec("sudo bash $script_path status 2>/dev/null");
            break;
    }
    exit;
}

// Handle FPP _menu parameter to prevent "page doesn't exist"
if (!isset($_GET['_menu'])) {
    $_GET['_menu'] = 'status';
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
    function runAction(action){
        const logDiv = document.getElementById('log');
        const authDiv = document.getElementById('authLink');

        fetch(`?action=${action}`)
        .then(response => response.text())
        .then(data => {
            if(action === 'install') {
                logDiv.innerText = data;
            }
            if(action === 'up' || action === 'down') {
                updateStatus();
            }
        });

        if(action === 'install') {
            fetch('?action=auth')
            .then(res => res.text())
            .then(link => {
                if(link){
                    authDiv.innerHTML = `<a href="${link}" target="_blank">Authorize Tailscale</a>`;
                    authDiv.style.display = 'block';
                }
            });
        }
    }

    function updateStatus(){
        fetch('?action=status')
        .then(res => res.json())
        .then(data => {
            const statusDiv = document.getElementById('status');
            const authDiv = document.getElementById('authLink');

            if(data && Object.keys(data).length){
                statusDiv.innerText = JSON.stringify(data, null, 2);
                authDiv.style.display = 'none';
            } else {
                statusDiv.innerText = "Tailscale not connected";
                authDiv.style.display = 'block';
                fetch('?action=auth')
                .then(res => res.text())
                .then(link => {
                    if(link) authDiv.innerHTML = `<a href="${link}" target="_blank">Authorize Tailscale</a>`;
                });
            }
        });
    }

    // Poll for status every 5 seconds
    setInterval(updateStatus, 5000);
    updateStatus();
</script>
</body>
</html>
