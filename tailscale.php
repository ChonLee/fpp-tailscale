<?php
/*
    Tailscale Plugin for FPP - tailscale.php
    Author: John Myers
    Description: Manage Tailscale from Falcon Player.
*/

// Optional: if called via AJAX for status
if (isset($_GET['ajax_status'])) {
    $output = shell_exec('sudo tailscale status 2>&1');
    echo $output ?: "Tailscale not running.";
    exit;
}

// Handle form submissions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['install_tailscale'])) {
        exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-install.sh 2>&1 > /dev/null &');
        $message = "Installing Tailscale...";
    } elseif (isset($_POST['uninstall_tailscale'])) {
        exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-uninstall.sh 2>&1 > /dev/null &');
        $message = "Uninstalling Tailscale...";
    } elseif (isset($_POST['start_tailscale'])) {
        exec('sudo tailscale up 2>&1 > /dev/null &');
        $message = "Starting Tailscale...";
    } elseif (isset($_POST['stop_tailscale'])) {
        exec('sudo tailscale down 2>&1 > /dev/null &');
        $message = "Stopping Tailscale...";
    }
}

// Path to authorization link
$authFile = '/home/fpp/media/plugins/fpp-tailscale/auth_url.txt';
$authLink = (file_exists($authFile)) ? trim(file_get_contents($authFile)) : '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>FPP Tailscale Plugin</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <!-- jQuery for AJAX -->
    <script src="js/jquery-latest.min.js"></script>

    <style>
        body { font-family: sans-serif; text-align: center; padding: 20px; }
        .button, input[type=submit] {
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
        #status {
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
</head>
<body>
    <h1>FPP Tailscale Plugin</h1>

    <?php if (!empty($message)) echo "<p><strong>$message</strong></p>"; ?>

    <p>This device can connect remotely through Tailscale.</p>

    <h2>Tailscale Status</h2>
    <div id="status">Loading status...</div>

    <h2>Authorize Tailscale</h2>
    <div id="auth-container">
        <?php
        if ($authLink && str_starts_with($authLink, 'https://login.tailscale.com')) {
            echo "<a class='button' href='$authLink' target='_blank'>Click here to authorize Tailscale</a>";
        } else {
            echo "Waiting for authorization link...";
        }
        ?>
    </div>

    <h2>Manage Tailscale</h2>
    <form method="post">
        <input type="submit" name="install_tailscale" value="Install Tailscale">
        <input type="submit" name="start_tailscale" value="Start Tailscale">
        <input type="submit" name="stop_tailscale" value="Stop Tailscale">
        <input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale">
    </form>

    <script>
    const statusContainer = document.getElementById('status');
    const authContainer = document.getElementById('auth-container');

    // Poll Tailscale status
    async function updateStatus() {
        try {
            const resp = await fetch('tailscale.php?ajax_status=1');
            const text = await resp.text();
            statusContainer.textContent = text;

            if (text.toLowerCase().includes('100%') || text.toLowerCase().includes('active')) {
                authContainer.innerHTML = "<p>Tailscale is authorized and running!</p>";
            }

            setTimeout(updateStatus, 3000);
        } catch (e) {
            setTimeout(updateStatus, 3000);
        }
    }

    // Poll for authorization link if not yet authorized
    async function updateAuthLink() {
        if (authContainer.textContent.includes('Waiting')) {
            try {
                const resp = await fetch('auth_url.txt');
                const link = (await resp.text()).trim();
                if (link.startsWith('https://login.tailscale.com')) {
                    authContainer.innerHTML = `<a class="button" href="${link}" target="_blank">Click here to authorize Tailscale</a>`;
                } else {
                    setTimeout(updateAuthLink, 2000);
                }
            } catch (e) {
                setTimeout(updateAuthLink, 2000);
            }
        }
    }

    updateStatus();
    updateAuthLink();
    </script>
</body>
</html>
