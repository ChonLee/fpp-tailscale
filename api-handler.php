<?php
/*
 * Tailscale plugin backend for FPP.
 *
 * Called via: plugin.php?plugin=fpp-tailscale&nopage=1&page=api-handler.php&action=...
 *
 * Keep this PHP 7.4-compatible: FPP 7 runs on Debian bullseye.
 */

// FPP's directories, from its config.php (loaded by plugin.php), so a relocated
// media directory works. The defaults are only a fallback.
define('TS_CONFIG_FILE', rtrim(isset($settings['configDirectory']) ? $settings['configDirectory'] : '/home/fpp/media/config', '/')
    . '/plugin.fpp-tailscale');
define('TS_LOG_FILE', rtrim(isset($settings['logDirectory']) ? $settings['logDirectory'] : '/home/fpp/media/logs', '/')
    . '/plugin-fpp-tailscale.log');
define('TS_CTL', __DIR__ . '/scripts/ts-ctl.sh');
// Serializes saveConfig's read-modify-write, so two quick changes can't undo
// each other. In the plugin's data directory (FPP's plugindata/).
define('TS_CONFIG_LOCK', rtrim(isset($settings['mediaDirectory']) ? $settings['mediaDirectory'] : '/home/fpp/media', '/')
    . '/plugindata/fpp-tailscale/config.lock');
// A stuck tailscaled must not hold a web server worker: every tailscale call
// here gives up after 10 seconds.
define('TS_TIMEOUT', 'timeout 10 ');

require_once __DIR__ . '/lan-routes.php';

function tsRespond($code, $data)
{
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function tsRun($cmd, &$rc = null)
{
    $out = array();
    exec($cmd, $out, $rc);
    return implode("\n", $out);
}

function tsCtl($command)
{
    $out = tsRun('sudo -n /bin/bash ' . escapeshellarg(TS_CTL) . ' ' . escapeshellarg($command) . ' 2>&1', $rc);
    return array('ok' => $rc === 0, 'output' => $out);
}

function tsBin()
{
    foreach (array('/usr/bin/tailscale', '/usr/local/bin/tailscale', '/usr/sbin/tailscale') as $path) {
        if (is_executable($path)) {
            return $path;
        }
    }
    return null;
}

function tsReadConfig()
{
    $cfg = array('auto_connect' => false, 'accept_routes' => false, 'hostname' => '');
    $ini = is_readable(TS_CONFIG_FILE) ? @parse_ini_file(TS_CONFIG_FILE, false, INI_SCANNER_TYPED) : false;
    if (is_array($ini)) {
        foreach (array('auto_connect', 'accept_routes') as $key) {
            if (isset($ini[$key])) {
                $cfg[$key] = filter_var($ini[$key], FILTER_VALIDATE_BOOLEAN);
            }
        }
        if (isset($ini['hostname'])) {
            $cfg['hostname'] = (string)$ini['hostname'];
        }
    }
    return $cfg;
}

// Same `key = "value"` format FPP uses for its own settings files.
function tsWriteConfig($cfg)
{
    $ini = 'auto_connect = "' . ($cfg['auto_connect'] ? 'true' : 'false') . "\"\n"
        . 'accept_routes = "' . ($cfg['accept_routes'] ? 'true' : 'false') . "\"\n"
        . 'hostname = "' . $cfg['hostname'] . "\"\n";
    $tmp = TS_CONFIG_FILE . '.tmp';
    if (@file_put_contents($tmp, $ini) === false) {
        return false;
    }
    @chmod($tmp, 0644);
    return @rename($tmp, TS_CONFIG_FILE);
}

function tsDecodeStatus($out)
{
    // Skip any warning text printed ahead of the JSON.
    $start = strpos($out, '{');
    if ($start === false) {
        return null;
    }
    $json = json_decode(substr($out, $start), true);
    return (is_array($json) && isset($json['BackendState'])) ? $json : null;
}

/*
 * Decoded `tailscale status --json`, or null with $error set. Non-root users
 * may read status, so sudo is only a fallback.
 */
function tsStatusJson($bin, &$error)
{
    $json = tsDecodeStatus(tsRun(TS_TIMEOUT . escapeshellarg($bin) . ' status --json 2>/dev/null'));
    if ($json === null) {
        $out = tsRun('sudo -n ' . TS_TIMEOUT . escapeshellarg($bin) . ' status --json 2>&1');
        $json = tsDecodeStatus($out);
        if ($json === null) {
            $lines = explode("\n", trim($out));
            $error = $lines[0];
        }
    }
    return $json;
}

// Tailscale's own automatic-update setting: true or false, or null if it
// can't be read (Tailscale not installed or not running). Falls back to sudo
// like tsStatusJson().
function tsAutoUpdate()
{
    $bin = tsBin();
    if ($bin === null) {
        return null;
    }
    foreach (array('', 'sudo -n ') as $prefix) {
        $prefs = json_decode(tsRun($prefix . TS_TIMEOUT . escapeshellarg($bin) . ' debug prefs 2>/dev/null'), true);
        if (is_array($prefs) && isset($prefs['AutoUpdate']) && is_array($prefs['AutoUpdate'])) {
            return !empty($prefs['AutoUpdate']['Apply']);
        }
    }
    return null;
}

// Read-only status: one `tailscale status --json` call, no side effects.
function tsStatus()
{
    $bin = tsBin();
    if ($bin === null) {
        return array('state' => 'not_installed');
    }

    $json = tsStatusJson($bin, $error);
    if ($json === null) {
        return array('state' => 'daemon_down', 'message' => $error);
    }

    $self = (isset($json['Self']) && is_array($json['Self'])) ? $json['Self'] : array();
    $backend = $json['BackendState'];

    if ($backend === 'NeedsLogin' || !empty($self['KeyExpired'])) {
        $authUrl = isset($json['AuthURL']) ? (string)$json['AuthURL'] : '';
        return array('state' => 'needs_auth', 'auth_url' => $authUrl);
    }
    if ($backend === 'NeedsMachineAuth') {
        return array('state' => 'needs_approval');
    }
    if ($backend === 'Stopped') {
        return array('state' => 'disconnected');
    }
    if ($backend !== 'Running') {
        return array('state' => 'starting');
    }

    $ip = '';
    if (!empty($self['TailscaleIPs']) && is_array($self['TailscaleIPs'])) {
        $ip = $self['TailscaleIPs'][0];
        foreach ($self['TailscaleIPs'] as $addr) {
            if (strpos($addr, '.') !== false) {
                $ip = $addr;
                break;
            }
        }
    }
    return array(
        'state' => 'connected',
        'ip' => $ip,
        'hostname' => isset($self['HostName']) ? $self['HostName'] : '',
        'dns_name' => isset($self['DNSName']) ? rtrim($self['DNSName'], '.') : '',
    );
}

// After starting `tailscale up`, wait briefly until there's something to show.
function tsWaitForSettled($seconds)
{
    $deadline = microtime(true) + $seconds;
    do {
        usleep(300000);
        $status = tsStatus();
        $state = $status['state'];
        if ($state === 'connected' || $state === 'needs_approval'
            || ($state === 'needs_auth' && $status['auth_url'] !== '')) {
            break;
        }
    } while (microtime(true) < $deadline);
    return $status;
}

function tsLogTail($maxLines)
{
    if (!is_readable(TS_LOG_FILE)) {
        return '';
    }
    $size = filesize(TS_LOG_FILE);
    $len = min($size, 16384);
    if ($len <= 0) {
        return '';
    }
    $fh = fopen(TS_LOG_FILE, 'rb');
    if ($fh === false) {
        return '';
    }
    fseek($fh, -$len, SEEK_END);
    $data = fread($fh, $len);
    fclose($fh);

    $lines = explode("\n", rtrim($data, "\n"));
    if ($len < $size) {
        array_shift($lines); // first line is probably partial
    }
    return implode("\n", array_slice($lines, -$maxLines));
}

$routes = array(
    'state' => 'GET',
    'status' => 'GET',
    'logs' => 'GET',
    'connect' => 'POST',
    'disconnect' => 'POST',
    'reauth' => 'POST',
    'saveConfig' => 'POST',
    'autoUpdate' => 'POST',
);
$action = isset($_GET['action']) ? $_GET['action'] : '';
$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : 'GET';

if (!isset($routes[$action])) {
    tsRespond(400, array('success' => false, 'message' => 'Unknown action'));
}
if ($method !== $routes[$action]) {
    tsRespond(405, array('success' => false, 'message' => "Use $routes[$action] for $action"));
}
// Cross-site request forgery: a page on another site can make a visitor's
// browser send a plain POST here, but it can't add this header without a CORS
// preflight, which FPP doesn't answer for plugin pages. jQuery adds it to the
// plugin page's own (same-origin) requests.
if ($method === 'POST' && (!isset($_SERVER['HTTP_X_REQUESTED_WITH']) || $_SERVER['HTTP_X_REQUESTED_WITH'] !== 'XMLHttpRequest')) {
    tsRespond(403, array('success' => false, 'message' => 'Missing X-Requested-With: XMLHttpRequest header'));
}

switch ($action) {
    case 'state':
        $hostname = gethostname();
        tsRespond(200, array(
            'success' => true,
            'status' => tsStatus(),
            'config' => tsReadConfig(),
            'auto_update' => tsAutoUpdate(),
            'system_hostname' => $hostname === false ? '' : $hostname,
        ));
        break;

    case 'status':
        tsRespond(200, array('success' => true, 'status' => tsStatus()));
        break;

    case 'logs':
        tsRespond(200, array('success' => true, 'logs' => tsLogTail(100)));
        break;

    case 'connect':
    case 'reauth':
        $result = tsCtl($action === 'connect' ? 'up' : 'reauth');
        if (!$result['ok']) {
            tsRespond(500, array('success' => false, 'message' => $result['output'], 'status' => tsStatus()));
        }
        tsRespond(200, array('success' => true, 'status' => tsWaitForSettled(10)));
        break;

    case 'disconnect':
        $result = tsCtl('down');
        tsRespond($result['ok'] ? 200 : 500, array(
            'success' => $result['ok'],
            'message' => $result['output'],
            'status' => tsStatus(),
        ));
        break;

    case 'saveConfig':
        $input = json_decode(file_get_contents('php://input'), true);
        if (!is_array($input)) {
            tsRespond(400, array('success' => false, 'message' => 'Invalid JSON input'));
        }

        // Held until the response is sent (tsRespond exits; PHP then releases it).
        $lockDir = dirname(TS_CONFIG_LOCK);
        if (!is_dir($lockDir)) {
            @mkdir($lockDir, 0755, true);
        }
        $lock = @fopen(TS_CONFIG_LOCK, 'c');
        if ($lock === false || !flock($lock, LOCK_EX)) {
            tsRespond(500, array('success' => false, 'message' => 'Could not lock ' . TS_CONFIG_LOCK));
        }

        $cfg = tsReadConfig();
        foreach (array('auto_connect', 'accept_routes') as $key) {
            if (array_key_exists($key, $input)) {
                $cfg[$key] = filter_var($input[$key], FILTER_VALIDATE_BOOLEAN);
            }
        }

        // Refuse routes that cover this FPP's own LAN: accepting them cuts the
        // FPP off from its local network. While connected the routes are known,
        // so check now, and refuse if the check can't be done. When not
        // connected, ts-ctl.sh checks (the same way) once it is.
        if (!empty($input['accept_routes']) && $cfg['accept_routes'] && tsBin() !== null) {
            $json = tsStatusJson(tsBin(), $error);
            if (is_array($json) && isset($json['BackendState']) && $json['BackendState'] === 'Running') {
                list($conflicts, $checkError) = tsRouteCheck($json);
                if ($checkError !== null) {
                    tsRespond(409, array(
                        'success' => false,
                        'message' => 'Not turned on: ' . $checkError . ', so the plugin couldn\'t check that accepting routes is safe.',
                    ));
                }
                if ($conflicts) {
                    tsRespond(409, array(
                        'success' => false,
                        'message' => 'Not turned on: ' . implode('; ', $conflicts)
                            . '. Accepting that route would cut this FPP off from your local network.',
                    ));
                }
            }
        }
        if (array_key_exists('hostname', $input)) {
            $hostname = trim((string)$input['hostname']);
            if ($hostname !== '' && !preg_match('/^[A-Za-z0-9]([A-Za-z0-9.-]{0,61}[A-Za-z0-9])?$/', $hostname)) {
                tsRespond(400, array(
                    'success' => false,
                    'message' => 'Invalid hostname: use letters, numbers, hyphens and dots, starting and ending with a letter or number',
                ));
            }
            $cfg['hostname'] = $hostname;
        }

        if (!tsWriteConfig($cfg)) {
            $error = error_get_last();
            tsRespond(500, array(
                'success' => false,
                'message' => 'Could not write ' . TS_CONFIG_FILE . ': ' . ($error ? $error['message'] : 'unknown error'),
            ));
        }

        // Apply hostname/route changes right away if we're connected.
        $applied = false;
        $status = tsStatus();
        if ($status['state'] === 'connected') {
            $applied = tsCtl('up')['ok'];
        }
        tsRespond(200, array('success' => true, 'config' => $cfg, 'applied' => $applied));
        break;

    // Not plugin config: it's Tailscale's own setting, so it's set directly and
    // read back from Tailscale (tsAutoUpdate), which keeps it right if it's
    // changed elsewhere.
    case 'autoUpdate':
        $input = json_decode(file_get_contents('php://input'), true);
        if (!is_array($input) || !array_key_exists('enabled', $input)) {
            tsRespond(400, array('success' => false, 'message' => 'Expected {"enabled": true|false}'));
        }
        $enabled = filter_var($input['enabled'], FILTER_VALIDATE_BOOLEAN);
        $result = tsCtl($enabled ? 'autoupdate-on' : 'autoupdate-off');
        tsRespond($result['ok'] ? 200 : 500, array(
            'success' => $result['ok'],
            'message' => $result['output'],
            'auto_update' => tsAutoUpdate(),
        ));
        break;
}
