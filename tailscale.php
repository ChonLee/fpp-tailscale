<?php
// tailscale.php - FPP Tailscale Plugin Page

$pluginDir = __DIR__; // plugin folder
$statusFile = "$pluginDir/install_status.txt";
$authFile   = "$pluginDir/auth_url.txt";

// Handle form actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['install_tailscale'])) {
        // Run install script in background
        shell_exec("nohup $pluginDir/scripts/fpp-install.sh > $statusFile 2>&1 &");
    } elseif (isset($_POST['start_tailscale'])) {
        shell_exec("sudo tailscale up >> $statusFile 2>&1 &");
    } elseif (isset($_POST['stop_tailscale'])) {
        shell_exec("sudo tailscale down >> $statusFile 2>&1 &");
    } elseif (isset($_POST['uninstall_tailscale'])) {
        shell_exec("sudo apt-get remove -y tailscale >> $statusFile 2>&1 &");
    }
}

// Ajax status update
if (isset($_GET['ajax_status'])) {
    if (file_exists($statusFile)) {
        echo file_get_contents($statusFile);
    } else {
        echo "No installation status yet.";
    }
    exit;
}

// Ajax auth link
if (isset($_GET['ajax_auth'])) {
    if (file_exists($authFile)) {
        echo file_get_contents($authFile);
    } else {
        echo "";
    }
    exit;
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>FPP Tailscale Plugin</title>
<style>
body { font-family: sans-serif; text-align: center; padding: 20px; }
.button, input[type=submit] {
    display: inline-block; padding: 10px 20px; font-size: 16px; margin: 5px;
    text-decoration: none; color: white; background-color: #0073e6;
    border-radius: 5px; border: none; cursor: pointer;
}
#status, #auth-container {
    font-family: monospace; white-space: pre; text-align: left;
    background: #f0f0f0; padding: 10px; border-radius: 5px; display: inline-block;
    min-width: 400px;
}
</style>
</head>
<body>

<h1>FPP Tailscale Plugin</h1>
<p>This device can connect remotely through Tailscale.</p>

<h2>Installation & Status</h2>
<div id="status">Waiting for installation...</div>

<h2>Authorize Tailscale</h2>
<div id="auth-container">Waiting for authorization link...</div>

<h2>Manage Tailscale</h2>
<form method="post">
    <input type="submit" name="install_tailscale" value="Install Tailscale">
    <input type="submit" name="start_tailscale" value="Start Tailscale">
    <input type="submit" name="stop_tailscale" value="Stop Tailscale">
    <input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale">
</form>

<script>
// Poll installation status
const statusContainer = document.getElementById('status');
async function updateInstallStatus() {
    try {
        const resp = await fetch('tailscale.php?ajax_status=1');
        const text = await resp.text();
        statusContainer.textContent = text || 'Waiting for installation...';
        setTimeout(updateInstallStatus, 2000);
    } catch(e) {
        setTimeout(updateInstallStatus, 2000);
    }
}

// Poll Tailscale auth link
const authContainer = document.getElementById('auth-container');
async function updateAuthLink() {
    try {
        const resp = await fetch('tailscale.php?ajax_auth=1');
        const link = (await resp.text()).trim();
        if(link.startsWith('https://login.tailscale.com')) {
            authContainer.innerHTML = `<a class="button" href="${link}" target="_blank">Click here to authorize Tailscale</a>`;
        } else {
            setTimeout(updateAuthLink, 2000);
        }
    } catch(e) {
        setTimeout(updateAuthLink, 2000);
    }
}

// Initialize polling
updateInstallStatus();
updateAuthLink();
</script>

</body>
</html>
