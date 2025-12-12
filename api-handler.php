<?php
/*
 * Tailscale Plugin API for FPP
 * Handles all backend operations for the Tailscale management interface
 * 
 * Called via: plugin.php?plugin=fpp-tailscale&nopage=1&page=api-handler.php&action=...
 */

$PLUGIN_VERSION = "2025.12.11.1";

header('Content-Type: application/json');

// Use FPP's standard config directory
$PLUGIN_NAME = "fpp-tailscale";
$CONFIG_DIR = "/home/fpp/media/config";
$CONFIG_FILE = "$CONFIG_DIR/plugin.$PLUGIN_NAME";
$LOG_FILE = "/var/log/fpp-tailscale.log";

// Ensure config directory exists
if (!is_dir($CONFIG_DIR)) {
    mkdir($CONFIG_DIR, 0755, true);
}

/**
 * Execute a shell command and return output
 */
function execCommand($cmd) {
    exec($cmd . " 2>&1", $output, $return_code);
    return [
        'output' => implode("\n", $output),
        'return_code' => $return_code
    ];
}

/**
 * Read configuration file (INI format)
 */
function readConfig() {
    global $CONFIG_FILE;
    
    // Get system hostname as default
    $systemHostname = trim(shell_exec('hostname') ?: 'fpp-player');
    
    $defaults = [
        'auto_connect' => false,
        'accept_routes' => false,
        'advertise_exit' => false,
        'hostname' => $systemHostname
    ];
    
    if (file_exists($CONFIG_FILE)) {
        $config = parse_ini_file($CONFIG_FILE);
        if ($config !== false) {
            // Convert string "true"/"false" to boolean
            foreach ($config as $key => $value) {
                if ($value === 'true' || $value === '1') {
                    $config[$key] = true;
                } elseif ($value === 'false' || $value === '0') {
                    $config[$key] = false;
                }
            }
            // Merge with defaults, but keep system hostname if not explicitly set
            $merged = array_merge($defaults, $config);
            
            // If hostname in config is empty or default, use system hostname
            if (empty($merged['hostname']) || $merged['hostname'] === 'fpp-player') {
                $merged['hostname'] = $systemHostname;
            }
            
            return $merged;
        }
    }
    
    return $defaults;
}

/**
 * Write configuration file (INI format)
 */
function writeConfig($config) {
    global $CONFIG_FILE, $CONFIG_DIR;
    
    // Ensure directory exists
    if (!is_dir($CONFIG_DIR)) {
        mkdir($CONFIG_DIR, 0777, true);
    }
    
    $iniContent = "; Tailscale Plugin Configuration\n";
    $iniContent .= "; Generated: " . date('Y-m-d H:i:s') . "\n\n";
    
    foreach ($config as $key => $value) {
        // Convert boolean to string
        if (is_bool($value)) {
            $value = $value ? 'true' : 'false';
        }
        $iniContent .= "$key = $value\n";
    }
    
    // Write the file
    $result = @file_put_contents($CONFIG_FILE, $iniContent);
    
    // Set proper permissions if file was created
    if ($result !== false && file_exists($CONFIG_FILE)) {
        @chmod($CONFIG_FILE, 0666);
    }
    
    return $result !== false;
}

/**
 * Get Tailscale status
 */
function getTailscaleStatus() {
    // Check if tailscaled is running
    $daemonCheck = execCommand("pgrep -x tailscaled");
    if ($daemonCheck['return_code'] !== 0) {
        return [
            'connected' => false,
            'status' => 'Tailscale daemon not running',
            'daemon_running' => false
        ];
    }
    
    // Get text status first to check login state
    $textStatus = execCommand("sudo tailscale status 2>&1");
    $statusOutput = $textStatus['output'];
    
    // Get detailed JSON status to check actual connection state
    $jsonResult = execCommand("sudo tailscale status --json 2>&1");
    $jsonStatus = null;
    if ($jsonResult['return_code'] === 0) {
        $jsonStatus = json_decode($jsonResult['output'], true);
    }
    
    // Check if device is revoked/expired in JSON status
    if ($jsonStatus && isset($jsonStatus['Self'])) {
        $self = $jsonStatus['Self'];
        
        // Check for revoked or expired state
        if (isset($self['KeyExpired']) && $self['KeyExpired'] === true) {
            // Key expired, need to re-authenticate
            execCommand("sudo tailscale logout 2>&1");
            
            $config = readConfig();
            $hostname = $config['hostname'] ?? 'fpp-player';
            $authResult = execCommand("timeout 3 sudo tailscale up --hostname={$hostname} 2>&1 || true");
            $authUrl = null;
            
            if (preg_match('/https:\/\/login\.tailscale\.com\/[^\s\'"<>]+/', $authResult['output'], $matches)) {
                $authUrl = $matches[0];
            }
            
            return [
                'connected' => false,
                'daemon_running' => true,
                'status' => 'Device revoked - authentication required',
                'auth_url' => $authUrl
            ];
        }
        
        // Check if actually connected with valid IP
        $hasIP = !empty($self['TailscaleIPs']) && !empty($self['TailscaleIPs'][0]);
        $isOnline = isset($self['Online']) && $self['Online'] === true;
        
        if ($hasIP && $isOnline) {
            return [
                'connected' => true,
                'daemon_running' => true,
                'ip' => $self['TailscaleIPs'][0],
                'hostname' => $self['HostName'] ?? 'N/A',
                'status' => 'Connected',
                'online' => true,
                'auth_url' => null
            ];
        }
    }
    
    // Not connected - check if needs login/authentication
    // Look for various "not logged in" indicators
    if (strpos($statusOutput, 'Logged out') !== false ||
        strpos($statusOutput, 'NeedsLogin') !== false ||
        strpos($statusOutput, 'run `tailscale up`') !== false ||
        strpos($statusOutput, 'not logged in') !== false ||
        strpos($statusOutput, 'expired') !== false ||
        strpos($statusOutput, 'revoked') !== false ||
        empty($statusOutput) ||
        trim($statusOutput) === '') {
        
        // Definitely needs auth - try to get URL
        $config = readConfig();
        $hostname = $config['hostname'] ?? 'fpp-player';
        
        $authResult = execCommand("timeout 3 sudo tailscale up --hostname={$hostname} 2>&1 || true");
        $authUrl = null;
        
        // Extract URL from output
        if (preg_match('/https:\/\/login\.tailscale\.com\/[^\s\'"<>]+/', $authResult['output'], $matches)) {
            $authUrl = $matches[0];
        }
        
        return [
            'connected' => false,
            'daemon_running' => true,
            'status' => 'Authentication required',
            'auth_url' => $authUrl
        ];
    }
    
    // Disconnected - show helpful message
    return [
        'connected' => false,
        'daemon_running' => true,
        'status' => 'Disconnected (click Connect, or use Authenticate if device was revoked)'
    ];
}

/**
 * Connect to Tailscale
 */
function connectTailscale() {
    $config = readConfig();
    
    $args = [];
    if ($config['accept_routes']) {
        $args[] = '--accept-routes';
    }
    if (!empty($config['hostname'])) {
        $args[] = '--hostname=' . escapeshellarg($config['hostname']);
    }
    
    $cmd = "sudo tailscale up " . implode(' ', $args);
    $result = execCommand($cmd);
    
    // Check if we got an auth URL
    $authUrl = null;
    if (preg_match('/https:\/\/login\.tailscale\.com\/[^\s]+/', $result['output'], $matches)) {
        $authUrl = $matches[0];
    }
    
    return [
        'success' => $result['return_code'] === 0 || $authUrl !== null,
        'message' => $result['output'],
        'auth_url' => $authUrl
    ];
}

/**
 * Disconnect from Tailscale
 */
function disconnectTailscale() {
    $result = execCommand("sudo tailscale down");
    return [
        'success' => $result['return_code'] === 0,
        'message' => $result['output']
    ];
}

/**
 * Get recent logs
 */
function getLogs() {
    global $LOG_FILE;
    
    if (file_exists($LOG_FILE)) {
        $lines = file($LOG_FILE);
        $recentLines = array_slice($lines, -50); // Last 50 lines
        return implode('', $recentLines);
    }
    
    return "No logs available";
}

// Main API router
$action = $_GET['action'] ?? '';

try {
    switch ($action) {
        case 'getStatus':
            $status = getTailscaleStatus();
            echo json_encode([
                'success' => true,
                'status' => $status
            ]);
            break;
            
        case 'getConfig':
            $config = readConfig();
            echo json_encode([
                'success' => true,
                'config' => $config
            ]);
            break;
            
        case 'saveConfig':
            // Get input from raw POST data
            $rawInput = file_get_contents('php://input');
            $input = json_decode($rawInput, true);
            
            // Debug logging
            error_log("Tailscale saveConfig - Raw input: " . substr($rawInput, 0, 200));
            error_log("Tailscale saveConfig - Parsed: " . print_r($input, true));
            error_log("Tailscale saveConfig - Config file: " . $CONFIG_FILE);
            
            if (!$input) {
                echo json_encode([
                    'success' => false,
                    'message' => 'Invalid JSON input'
                ]);
                break;
            }
            
            // Ensure config file is writable
            if (file_exists($CONFIG_FILE) && !is_writable($CONFIG_FILE)) {
                echo json_encode([
                    'success' => false,
                    'message' => 'Config file not writable: ' . $CONFIG_FILE
                ]);
                break;
            }
            
            if (writeConfig($input)) {
                echo json_encode([
                    'success' => true,
                    'message' => 'Configuration saved successfully'
                ]);
            } else {
                $error = error_get_last();
                echo json_encode([
                    'success' => false,
                    'message' => 'Failed to write config file: ' . ($error['message'] ?? 'Unknown error')
                ]);
            }
            break;
            
        case 'connect':
            $result = connectTailscale();
            echo json_encode($result);
            break;
            
        case 'disconnect':
            $result = disconnectTailscale();
            echo json_encode($result);
            break;
            
        case 'logout':
            $result = execCommand("sudo tailscale logout 2>&1");
            echo json_encode([
                'success' => $result['return_code'] === 0,
                'message' => $result['output']
            ]);
            break;
            
        case 'getSystemInfo':
            $systemHostname = trim(shell_exec('hostname') ?: 'unknown');
            echo json_encode([
                'success' => true,
                'hostname' => $systemHostname
            ]);
            break;
            
        case 'getLogs':
            $logs = getLogs();
            echo json_encode([
                'success' => true,
                'logs' => $logs
            ]);
            break;
            
        default:
            echo json_encode([
                'success' => false,
                'message' => 'Unknown action: ' . $action
            ]);
    }
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Error: ' . $e->getMessage()
    ]);
}
