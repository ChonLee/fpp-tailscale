<?php
/*
 * Finds subnet routes advertised on the tailnet that overlap this device's own
 * LAN. Accepting such a route sends the FPP's LAN replies into Tailscale and
 * cuts it off from its local network.
 *
 * Included by api-handler.php. Also run by scripts/ts-ctl.sh as
 *   php lan-routes.php
 * which prints one conflict per line and exits 1 if there are any, or prints
 * why it couldn't check and exits 2. Only exit 0 means it's safe.
 *
 * Keep this PHP 7.4-compatible, and safe on 32-bit PHP (no unsigned IPv4 math).
 */

// IPv4 networks on this device's real interfaces, e.g. eth0 192.168.1.5/24.
function tsLocalNetworks()
{
    $ip = null;
    foreach (array('/usr/sbin/ip', '/sbin/ip', '/usr/bin/ip', '/bin/ip') as $path) {
        if (is_executable($path)) {
            $ip = $path;
            break;
        }
    }
    if ($ip === null) {
        return array();
    }
    $lines = array();
    exec(escapeshellarg($ip) . ' -4 -o addr show scope global 2>/dev/null', $lines);
    $nets = array();
    foreach ($lines as $line) {
        if (preg_match('/^\d+:\s+(\S+)\s+inet\s+([\d.]+)\/(\d+)/', $line, $m) && strpos($m[1], 'tailscale') !== 0) {
            $nets[] = array('iface' => $m[1], 'addr' => $m[2], 'prefix' => (int)$m[3]);
        }
    }
    return $nets;
}

// 32-character bit string for an IPv4 address (works on 32- and 64-bit PHP).
function tsIpBits($ip)
{
    $long = ip2long($ip);
    return $long === false ? null : substr(sprintf('%032b', $long), -32);
}

function tsCidrOverlap($a, $aPrefix, $b, $bPrefix)
{
    $prefix = min($aPrefix, $bPrefix);
    $x = tsIpBits($a);
    $y = tsIpBits($b);
    return $x !== null && $y !== null && substr($x, 0, $prefix) === substr($y, 0, $prefix);
}

// $status is decoded `tailscale status --json`; $nets defaults to tsLocalNetworks().
function tsRouteConflicts($status, $nets = null)
{
    $conflicts = array();
    if (!is_array($status) || empty($status['Peer']) || !is_array($status['Peer'])) {
        return $conflicts;
    }
    if ($nets === null) {
        $nets = tsLocalNetworks();
    }
    foreach ($status['Peer'] as $peer) {
        if (empty($peer['PrimaryRoutes']) || !is_array($peer['PrimaryRoutes'])) {
            continue;
        }
        $name = !empty($peer['HostName']) ? $peer['HostName'] : 'Another Tailscale device';
        foreach ($peer['PrimaryRoutes'] as $route) {
            // Skip IPv6 and default routes (exit nodes are a separate setting).
            if (!preg_match('/^([\d.]+)\/(\d+)$/', $route, $m) || (int)$m[2] === 0) {
                continue;
            }
            foreach ($nets as $net) {
                if (tsCidrOverlap($m[1], (int)$m[2], $net['addr'], $net['prefix'])) {
                    $conflicts[] = "$name shares $route, which is this FPP's own network ({$net['iface']})";
                }
            }
        }
    }
    return array_values(array_unique($conflicts));
}

// Like tsRouteConflicts(), but also says when the check couldn't be done, so
// callers refuse instead of treating "couldn't tell" as safe. Returns
// array(conflicts, error); error is null when the check ran.
function tsRouteCheck($status, $nets = null)
{
    if (!is_array($status) || !isset($status['BackendState'])) {
        return array(array(), "Couldn't read Tailscale's status");
    }
    if ($nets === null) {
        $nets = tsLocalNetworks();
    }
    if (!$nets) {
        return array(array(), "Couldn't read this FPP's own network addresses");
    }
    return array(tsRouteConflicts($status, $nets), null);
}

if (PHP_SAPI === 'cli' && isset($argv[0]) && realpath($argv[0]) === __FILE__) {
    $out = (string)shell_exec('timeout 10 tailscale status --json 2>/dev/null');
    $start = strpos($out, '{');
    list($conflicts, $error) = tsRouteCheck($start === false ? null : json_decode(substr($out, $start), true));
    if ($error !== null) {
        echo $error, "\n";
        exit(2);
    }
    if ($conflicts) {
        echo implode("\n", $conflicts), "\n";
        exit(1);
    }
    exit(0);
}
