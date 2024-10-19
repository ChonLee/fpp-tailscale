<?php
/*
Plugin Name: FPP Tailscale
Description: A plugin to install and manage Tailscale on your FPP device.
Version: 1.0
Author: John Myers
*/

// Check if we are on the status page or regular UI
if (isset($_GET['page']) && $_GET['page'] == 'status') {
    // Tailscale Status Page

    echo "<h1>Tailscale Status</h1>";
    $output = shell_exec('sudo tailscale status 2>&1');
    if ($output) {
        echo "<pre>$output</pre>";
    } else {
        echo "<p>Unable to retrieve Tailscale status.</p>";
    }

    // Include the same control buttons here for convenience
    echo "<h2>Manage Tailscale</h2>";
    echo '<form method="post">';
    echo '<input type="submit" name="install_tailscale" value="Install Tailscale"><br>';
    echo '<input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale"><br>';
    echo '<input type="submit" name="start_tailscale" value="Start Tailscale"><br>';
    echo '<input type="submit" name="stop_tailscale" value="Stop Tailscale"><br>';
    echo '<input type="submit" name="status_tailscale" value="Check Tailscale Status"><br>';
    echo '</form>';

    // Handle form submission
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (isset($_POST['install_tailscale'])) {
            $install_output = shell_exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-install.sh 2>&1');
            echo <pre>$install_output</pre>"Installing Tailscale...<br>";
        } elseif (isset($_POST['uninstall_tailscale'])) {
            exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-uninstall.sh');
            echo "Uninstalling Tailscale...<br>";
        } elseif (isset($_POST['start_tailscale'])) {
            exec('sudo tailscale up');
            echo "Starting Tailscale...<br>";
        } elseif (isset($_POST['stop_tailscale'])) {
            exec('sudo tailscale down');
            echo "Stopping Tailscale...<br>";
        } elseif (isset($_POST['status_tailscale'])) {
            $output = shell_exec('sudo tailscale status 2>&1');
            echo "<pre>$output</pre>";
        }
    }

    // Optionally add a back button
    echo '<form method="post" action="tailscale.php?plugin=fpp-tailscale">';
    echo '<input type="submit" value="Back to Tailscale Menu">';
    echo '</form>';
} else {
    // Main Plugin UI

    echo "<h1>FPP-Tailscale Plugin</h1>";
    echo "<p>Use this plugin to manage Tailscale on your FPP device.</p>";

    // Display the form controls
    echo '<form method="post">';
    echo '<input type="submit" name="install_tailscale" value="Install Tailscale"><br>';
    echo '<input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale"><br>';
    echo '<input type="submit" name="start_tailscale" value="Start Tailscale"><br>';
    echo '<input type="submit" name="stop_tailscale" value="Stop Tailscale"><br>';
    echo '<input type="submit" name="status_tailscale" value="Check Tailscale Status"><br>';
    echo '<input type="submit" name="tailscale_status_page" value="View Tailscale Status Page"><br>';
    echo '</form>';

    // Handle form submission
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (isset($_POST['install_tailscale'])) {
            exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-install.sh');
            echo "Installing Tailscale...<br>";
        } elseif (isset($_POST['uninstall_tailscale'])) {
            exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-uninstall.sh');
            echo "Uninstalling Tailscale...<br>";
        } elseif (isset($_POST['start_tailscale'])) {
            exec('sudo tailscale up');
            echo "Starting Tailscale...<br>";
        } elseif (isset($_POST['stop_tailscale'])) {
            exec('sudo tailscale down');
            echo "Stopping Tailscale...<br>";
        } elseif (isset($_POST['status_tailscale'])) {
            $output = shell_exec('sudo tailscale status 2>&1');
            echo "<pre>$output</pre>";
        } elseif (isset($_POST['tailscale_status_page'])) {
            // Redirect to the status page
            header("Location: tailscale.php?plugin=fpp-tailscale&page=status");
            exit;
        }
    }

    // Display the authorization URL if it exists
    $auth_url_file = '/home/fpp/media/plugins/fpp-tailscale/auth_url.txt';
    if (file_exists($auth_url_file)) {
        $auth_url = file_get_contents($auth_url_file);
        if ($auth_url) {
            echo "<p><strong>Authorize Tailscale:</strong> <a href='$auth_url' target='_blank'>$auth_url</a></p>";
        } else {
            echo "<p>Tailscale is running and authorized.</p>";
        }
    }
}
