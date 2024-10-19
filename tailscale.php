<?php
/*
Plugin Name: FPP Tailscale
Description: A plugin to install and manage Tailscale on your FPP device.
Version: 1.0
Author: John Myers
*/

function plugin_setup() {
    // Initialization code, if needed
}

function plugin_install() {
    exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-install.sh');
}

function plugin_uninstall() {
    exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-uninstall.sh');
}

function plugin_ui() {
    echo "<h1>FPP-Tailscale Plugin</h1>";
    echo "<p>Use this plugin to manage Tailscale on your FPP device.</p>";

    // Add control buttons
    echo '<form method="post">';
    echo '<input type="submit" name="install_tailscale" value="Install Tailscale"><br>';
    echo '<input type="submit" name="uninstall_tailscale" value="Uninstall Tailscale"><br>';
    echo '<input type="submit" name="start_tailscale" value="Start Tailscale"><br>';
    echo '<input type="submit" name="stop_tailscale" value="Stop Tailscale"><br>';
    echo '<input type="submit" name="status_tailscale" value="Check Tailscale Status"><br>';
    echo '<input type="submit" name="tailscale_status_page" value="View Tailscale Status Page"><br>';
    echo '</form>';

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (isset($_POST['install_tailscale'])) {
            exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-install.sh');
        } elseif (isset($_POST['uninstall_tailscale'])) {
            exec('/home/fpp/media/plugins/fpp-tailscale/scripts/fpp-uninstall.sh');
        } elseif (isset($_POST['start_tailscale'])) {
            exec('sudo tailscale up');
        } elseif (isset($_POST['stop_tailscale'])) {
            exec('sudo tailscale down');
        } elseif (isset($_POST['status_tailscale'])) {
            $output = shell_exec('sudo tailscale status');
            echo "<pre>$output</pre>";
        } elseif (isset($_POST['tailscale_status_page'])) {
            header("Location: plugin.php?plugin=fpp-tailscale&page=status");
            exit;
        }
    }
}

function plugin_status_page() {
    echo "<h1>Tailscale Status</h1>";
    $output = shell_exec('sudo tailscale status');
    if ($output) {
        echo "<pre>$output</pre>";
    } else {
        echo "<p>Unable to retrieve Tailscale status.</p>";
    }

    echo '<form method="post" action="plugin.php?plugin=fpp-tailscale">';
    echo '<input type="submit" value="Back to Tailscale Menu">';
    echo '</form>';
}
?>
