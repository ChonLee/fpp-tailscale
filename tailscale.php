<?php
/*
FPP Tailscale Plugin
Author: John Myers
Description: Manage Tailscale directly from FPP.
*/

$plugin_dir = __DIR__;
$auth_url_file = $plugin_dir . '/auth_url.txt';

// Function to get Tailscale status
function getTailscaleStatus() {
    $output = shell_exec('sudo tailscale status 2>&1');
    return $output ? htmlspecialchars($output) : "Unable to retrieve Tailscale status.";
}

// Handle optional AJAX call to update status dynamically
if (isset($_GET['ajax_status'])) {
    echo getTailscaleStatus();
    exit;
}

// Handle form submission for install/start/stop/uninstall
$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['install_tailscale'])) {
        exec("$plugin_dir/scripts/install.sh 2>&1 > /dev/null &");
        $message = "Installing Tailscale...";
    } elseif (isset($_POST['uninstall_tailscale'])) {
        exec("$plugin_dir/scripts/uninstall.sh 2>&1 > /dev/null &");
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
<!-- Plugin content starts here -->
<h1>FPP Tailscale Plugin</h1>
<p>This device can connect remotely through Tailscale.</p>

<?php if (!empty($message)) echo "<p><strong>$message</strong></p>"; ?>

<h2>Tailscale Status</h2>
<pre id="status"><?php echo getTailscaleStatus(); ?></pre>

<h2>Authorize Tailscale</h2>
<div id="auth-container">
    <p>Waiting for Tailscale authorization link...</p>
</div>

<h2>Manage Tailscale</h2>
<form method="post">
    <input type="submit" name="install_tailscale" value="Install Tailscale">
    <input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale"><br>
    <input type="submit" name="start_tailscale" value="Start Tailscale">
    <input type="submit" name="stop_tailscale" value="Stop Tailscale">
</form>

<script>
const authContainer = document.getElementById('auth-container');
const statusPre = document.getElementById('status');

// Poll auth_url.txt for the auth link
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
        const response = await fetch('?ajax_status=1');
        const newStatus = await response.text();
        statusPre.textContent = newStatus;

        if (newStatus.toLowerCase().includes('100%') || newStatus.toLowerCase().includes('active')) {
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

<style>
body { font-family: sans-serif; text-align: center; padding: 20px; }
a.button, input[type=submit] {
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
pre { text-align: left; display: inline-block; padding: 10px; background: #f0f0f0; border-radius: 5px; }
</style>
