<?php
/*
Plugin Name: FPP Tailscale
Description: Fully automatic Tailscale management plugin for FPP.
Version: 1.1
Author: John Myers
*/

$plugin_dir = '/home/fpp/media/plugins/fpp-tailscale';
$auth_url_file = $plugin_dir . '/auth_url.txt';

// Function to get Tailscale status
function getTailscaleStatus() {
    $output = shell_exec('sudo tailscale status 2>&1');
    if ($output) {
        return htmlspecialchars($output);
    } else {
        return "Unable to retrieve Tailscale status.";
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>FPP Tailscale Plugin</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding: 20px; }
        a.button {
            display: inline-block;
            padding: 10px 20px;
            font-size: 18px;
            text-decoration: none;
            color: white;
            background-color: #0073e6;
            border-radius: 5px;
            margin-top: 20px;
        }
        pre { text-align: left; display: inline-block; padding: 10px; background: #f0f0f0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>FPP Tailscale Plugin</h1>
    <p>This device can connect remotely through Tailscale.</p>

    <h2>Tailscale Status</h2>
    <pre id="status"><?php echo getTailscaleStatus(); ?></pre>

    <h2>Authorize Tailscale</h2>
    <div id="auth-container">
        <p>Waiting for Tailscale authorization link...</p>
    </div>

    <script>
        const authContainer = document.getElementById('auth-container');
        const statusPre = document.getElementById('status');

        // Poll auth_url.txt for the link
        async function updateAuthLink() {
            try {
                const response = await fetch('auth_url.txt');
                const authLink = (await response.text()).trim();
                if (authLink && authLink.startsWith('https://login.tailscale.com')) {
                    authContainer.innerHTML = `<a class="button" href="${authLink}" target="_blank">Click here to authorize Tailscale</a>`;
                } else {
                    setTimeout(updateAuthLink, 2000);
                }
            } catch (err) {
                setTimeout(updateAuthLink, 2000);
            }
        }

        // Poll Tailscale status every 3 seconds
        async function updateStatus() {
            try {
                const response = await fetch('tailscale_status.php'); // We'll create this next
                const newStatus = await response.text();
                statusPre.textContent = newStatus;

                // If status shows device is online, remove auth link
                if (newStatus.includes('100%') || newStatus.includes('active')) { // Adjust depending on tailscale status output
                    authContainer.innerHTML = "<p>Tailscale is authorized and running!</p>";
                }

                setTimeout(updateStatus, 3000);
            } catch (err) {
                setTimeout(updateStatus, 3000);
            }
        }

        updateAuthLink();
        updateStatus();
    </script>
</body>
</html>
