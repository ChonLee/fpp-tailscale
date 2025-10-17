<?php
$output = shell_exec('sudo tailscale status 2>&1');
if ($output) {
    echo htmlspecialchars($output);
} else {
    echo "Unable to retrieve Tailscale status.";
}