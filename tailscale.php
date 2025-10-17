<?php
/*
FPP Tailscale Plugin
Author: John Myers
Description: Manage Tailscale from FPP.
*/

$plugin_dir = __DIR__;
$auth_file = $plugin_dir . '/auth_url.txt';

// Handle AJAX request for status
if (isset($_GET['ajax_status'])) {
    echo shell_exec('sudo tailscale status 2>&1');
    exit;
}

// Handle plugin form submissions
$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['install_tailscale'])) {
        exec("$plugin_dir/scripts/install.sh > /dev/null 2>&1 &");
        $message = "Installing Tailscale...";
    } elseif (isset($_POST['uninstall_tailscale'])) {
        exec("$plugin_dir/scripts/uninstall.sh > /dev/null 2>&1 &");
        $message = "Uninstalling Tailscale...";
    } elseif (isset($_POST['start_tailscale'])) {
        exec('sudo tailscale up 2>&1', $output);
        $message = "Starting Tailscale...";
    } elseif (isset($_POST['stop_tailscale'])) {
        exec('sudo tailscale down 2>&1', $output);
        $message = "Stopping Tailscale...";
    }
}
?>

<div class="fpp-tailscale-plugin">
    <h1>FPP Tailscale Plugin</h1>

    <?php if (!empty($message)) echo "<p><strong>$message</strong></p>"; ?>

    <p>This device can connect remotely through Tailscale.</p>

    <h2>Tailscale Status</h2>
    <div id="status">Loading status...</div>

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
    const authContainer = document.getElementById('auth-container');
    const statusContainer = document.getElementById('status');

    // Poll auth_url.txt for authorization link
    async function updateAuthLink() {
        try {
            const resp = await fetch('auth_url.txt');
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

    // Poll Tailscale status every 3 seconds
    async function updateStatus() {
        try {
            const resp = await fetch('?ajax_status=1');
            const text = await resp.text();
            statusContainer.textContent = text;

            if (text.toLowerCase().includes('100%') || text.toLowerCase().includes('active')) {
                authContainer.innerHTML = "<p>Tailscale is authorized and running!</p>";
            }

            setTimeout(updateStatus, 3000);
        } catch(e) {
            setTimeout(updateStatus, 3000);
        }
    }

    updateAuthLink();
    updateStatus();
    </script>

    <style>
    .fpp-tailscale-plugin {
        font-family: sans-serif;
        text-align: center;
        padding: 20px;
    }
    .fpp-tailscale-plugin a.button,
    .fpp-tailscale-plugin input[type=submit] {
        display: inline-block;
        padding: 10px 20px;
        font-size: 16px;
        margin: 5px;
        text-decoration: none;
        color: white;
        background-color: #0073e6;
        border-radius: 5px;
        border: none;
        cursor: pointer;
    }
    .fpp-tailscale-plugin #status {
        font-family: monospace;
        white-space: pre;
        text-align: left;
        background: #f0f0f0;
        padding: 10px;
        display: inline-block;
        border-radius: 5px;
        min-width: 400px;
    }
    </style>
</div>
