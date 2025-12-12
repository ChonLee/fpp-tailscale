<!DOCTYPE html>
<html>
<head>
    <title>Tailscale Management</title>
    <style>
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }
        .status-box {
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
            border-left: 4px solid #2196F3;
            background-color: #E3F2FD;
        }
        .status-box.connected {
            border-left-color: #4CAF50;
            background-color: #E8F5E9;
        }
        .status-box.disconnected {
            border-left-color: #F44336;
            background-color: #FFEBEE;
        }
        .button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            margin: 5px;
        }
        .button:hover {
            background-color: #45a049;
        }
        .button.secondary {
            background-color: #2196F3;
        }
        .button.secondary:hover {
            background-color: #0b7dda;
        }
        .button.danger {
            background-color: #F44336;
        }
        .button.danger:hover {
            background-color: #da190b;
        }
        .form-group {
            margin: 15px 0;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
            color: #555;
        }
        .form-group input[type="text"] {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        .form-group input[type="checkbox"] {
            margin-right: 8px;
        }
        .info-table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        .info-table td {
            padding: 8px;
            border-bottom: 1px solid #ddd;
        }
        .info-table td:first-child {
            font-weight: bold;
            width: 30%;
            color: #555;
        }
        .auth-url {
            background-color: #FFF9C4;
            padding: 15px;
            border-radius: 4px;
            margin: 15px 0;
            word-break: break-all;
        }
        .auth-url a {
            color: #1976D2;
            text-decoration: none;
        }
        .auth-url a:hover {
            text-decoration: underline;
        }
        .log-box {
            background-color: #263238;
            color: #AED581;
            padding: 15px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 300px;
            overflow-y: auto;
            margin: 15px 0;
        }
        .loading {
            text-align: center;
            padding: 40px;
            color: #666;
        }
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #4CAF50;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 Tailscale VPN Management</h1>
        
        <div id="loading" class="loading">
            <div class="spinner"></div>
            <p>Loading Tailscale status...</p>
        </div>
        
        <div id="content" style="display:none;">
            <!-- Status Section -->
            <div id="status-section">
                <h2>Connection Status</h2>
                <div id="status-box" class="status-box">
                    <p id="status-text">Checking status...</p>
                </div>
                
                <div id="connection-info" style="display:none;">
                    <table class="info-table">
                        <tr>
                            <td>Tailscale IP:</td>
                            <td id="tailscale-ip">-</td>
                        </tr>
                        <tr>
                            <td>Hostname:</td>
                            <td id="hostname">-</td>
                        </tr>
                        <tr>
                            <td>Status:</td>
                            <td id="connection-status">-</td>
                        </tr>
                    </table>
                </div>
                
                <div id="auth-url-box" class="auth-url" style="display:none;">
                    <strong>⚠️ Authentication Required</strong>
                    <p>Please authenticate your device by clicking the link below:</p>
                    <a id="auth-url-link" href="#" target="_blank">Authenticate with Tailscale</a>
                </div>
                
                <div>
                    <button id="btn-authenticate" class="button" onclick="authenticateTailscale()" style="display:none;">🔑 Authenticate</button>
                    <button id="btn-connect" class="button" onclick="connectTailscale()">Connect</button>
                    <button id="btn-disconnect" class="button danger" onclick="disconnectTailscale()">Disconnect</button>
                    <button id="btn-reauth" class="button secondary" onclick="forceReauthenticate()" style="display:none;">🔄 Force Re-authenticate</button>
                    <button id="btn-refresh" class="button secondary" onclick="refreshStatus()">Refresh Status</button>
                </div>
            </div>
            
            <!-- Configuration Section -->
            <div id="config-section">
                <h2>Configuration</h2>
                
                <div class="form-group">
                    <label>
                        <input type="checkbox" id="auto-connect" onchange="saveConfig()">
                        Auto-connect on boot
                    </label>
                </div>
                
                <div class="form-group">
                    <label>
                        <input type="checkbox" id="accept-routes" onchange="saveConfig()">
                        Accept subnet routes
                    </label>
                </div>
                
                <div class="form-group">
                    <label for="hostname-input">Device Hostname:</label>
                    <input type="text" id="hostname-input" placeholder="fpp-player" value="fpp-player">
                    <small id="system-hostname-info" style="display:block; margin-top: 5px; color: #666;">
                        Current system hostname: <strong id="system-hostname">Loading...</strong>
                        <button class="button secondary" onclick="useSystemHostname()" style="padding: 5px 10px; font-size: 12px; margin-left: 10px;">Use System Hostname</button>
                    </small>
                    <button class="button secondary" onclick="saveConfig()" style="margin-top: 10px;">Save Configuration</button>
                </div>
            </div>
            
            <!-- Logs Section -->
            <div id="logs-section">
                <h2>Recent Logs</h2>
                <div id="log-content" class="log-box">
                    No logs available
                </div>
                <button class="button secondary" onclick="refreshLogs()">Refresh Logs</button>
            </div>
        </div>
    </div>

    <script>
        // Build the correct API path for this plugin
        var apiBase = 'plugin.php?plugin=fpp-tailscale&nopage=1&page=api-handler.php';
        
        // Load status on page load
        jQuery(document).ready(function($) {
            loadConfig();
            refreshStatus();
        });

        function loadConfig() {
            // Get system hostname first
            jQuery.get(apiBase + '&action=getSystemInfo', function(sysInfo) {
                if (sysInfo.success) {
                    var systemHostname = sysInfo.hostname;
                    jQuery('#system-hostname').text(systemHostname);
                    
                    // Then load saved config
                    jQuery.get(apiBase + '&action=getConfig', function(data) {
                        if (data.success) {
                            jQuery('#auto-connect').prop('checked', data.config.auto_connect);
                            jQuery('#accept-routes').prop('checked', data.config.accept_routes);
                            
                            // If saved hostname is empty or default, use system hostname
                            var savedHostname = data.config.hostname;
                            if (!savedHostname || savedHostname === 'fpp-player') {
                                jQuery('#hostname-input').val(systemHostname);
                            } else {
                                jQuery('#hostname-input').val(savedHostname);
                            }
                        }
                    });
                }
            });
        }

        function useSystemHostname() {
            var systemHostname = jQuery('#system-hostname').text();
            jQuery('#hostname-input').val(systemHostname);
            saveConfig();
        }

        function saveConfig() {
            const config = {
                auto_connect: jQuery('#auto-connect').is(':checked'),
                accept_routes: jQuery('#accept-routes').is(':checked'),
                hostname: jQuery('#hostname-input').val()
            };
            
            jQuery.ajax({
                url: apiBase + '&action=saveConfig',
                type: 'POST',
                contentType: 'application/json',
                data: JSON.stringify(config),
                dataType: 'json',
                success: function(data) {
                    if (data.success) {
                        alert('Configuration saved successfully!');
                    } else {
                        alert('Error saving configuration: ' + data.message);
                    }
                },
                error: function(xhr, status, error) {
                    alert('Error saving configuration: ' + error);
                    console.error('Save error:', xhr.responseText);
                }
            });
        }

        function refreshStatus() {
            jQuery.get(apiBase + '&action=getStatus', function(data) {
                jQuery('#loading').hide();
                jQuery('#content').show();
                
                if (data.success) {
                    const status = data.status;
                    
                    if (status.connected) {
                        jQuery('#status-box').removeClass('disconnected').addClass('connected');
                        jQuery('#status-text').html('<strong>✓ Connected to Tailscale</strong>');
                        jQuery('#connection-info').show();
                        jQuery('#tailscale-ip').text(status.ip || 'N/A');
                        jQuery('#hostname').text(status.hostname || 'N/A');
                        jQuery('#connection-status').text(status.status || 'Connected');
                        jQuery('#btn-authenticate').hide();
                        jQuery('#btn-connect').hide();
                        jQuery('#btn-reauth').hide();
                        jQuery('#btn-disconnect').show();
                        jQuery('#auth-url-box').hide();
                    } else {
                        jQuery('#status-box').removeClass('connected').addClass('disconnected');
                        jQuery('#connection-info').hide();
                        jQuery('#btn-disconnect').hide();
                        
                        // Check if we need authentication (auth_url present)
                        if (status.auth_url) {
                            jQuery('#status-text').html('<strong>✗ Authentication Required</strong><br><small>' + (status.status || 'Not logged in') + '</small>');
                            jQuery('#btn-authenticate').show();
                            jQuery('#btn-connect').hide();
                            jQuery('#btn-reauth').hide();
                            jQuery('#auth-url-box').show();
                            jQuery('#auth-url-link').attr('href', status.auth_url).text(status.auth_url);
                        } else {
                            jQuery('#status-text').html('<strong>✗ Disconnected from Tailscale</strong><br><small>' + (status.status || 'Ready to connect') + '</small>');
                            jQuery('#btn-authenticate').hide();
                            jQuery('#btn-connect').show();
                            jQuery('#btn-reauth').show(); // Show re-auth option
                            jQuery('#auth-url-box').hide();
                        }
                    }
                } else {
                    jQuery('#status-box').removeClass('connected').addClass('disconnected');
                    jQuery('#status-text').html('<strong>Error:</strong> ' + (data.message || 'Unknown error'));
                }
            }).fail(function(xhr, status, error) {
                jQuery('#loading').hide();
                jQuery('#content').show();
                jQuery('#status-box').removeClass('connected').addClass('disconnected');
                jQuery('#status-text').html('<strong>Error loading status:</strong> ' + error);
                console.error('API Error:', xhr.responseText);
            });
        }

        function authenticateTailscale() {
            jQuery('#status-text').html('Generating authentication URL...');
            jQuery.post(apiBase + '&action=connect', function(data) {
                if (data.auth_url) {
                    // Show the auth URL
                    jQuery('#status-text').html('<strong>✗ Authentication Required</strong>');
                    jQuery('#auth-url-box').show();
                    jQuery('#auth-url-link').attr('href', data.auth_url).text(data.auth_url);
                    
                    // Open in new window
                    window.open(data.auth_url, '_blank');
                    
                    // Poll for status after authentication
                    alert('Opening Tailscale authentication in new window.\n\nAfter authenticating, click "Refresh Status" or wait a moment.');
                    
                    // Auto-refresh after 10 seconds to check if authenticated
                    setTimeout(function() {
                        refreshStatus();
                    }, 10000);
                } else if (data.success) {
                    // Already authenticated, just connected
                    alert('Already authenticated! Connecting...');
                    setTimeout(refreshStatus, 2000);
                } else {
                    alert('Error: ' + data.message);
                    refreshStatus();
                }
            });
        }

        function forceReauthenticate() {
            if (confirm('This will log out and generate a new authentication URL.\n\nUse this if your device was revoked from Tailscale admin.\n\nContinue?')) {
                jQuery('#status-text').html('Logging out and generating new auth URL...');
                
                // Call logout action first
                jQuery.post(apiBase + '&action=logout', function(logoutData) {
                    // Then get new auth URL
                    setTimeout(function() {
                        authenticateTailscale();
                    }, 2000);
                });
            }
        }

        function connectTailscale() {
            jQuery('#status-text').html('Connecting to Tailscale...');
            jQuery.post(apiBase + '&action=connect', function(data) {
                if (data.auth_url) {
                    // Authentication required - show the URL
                    jQuery('#status-text').html('<strong>Authentication Required</strong>');
                    jQuery('#auth-url-box').show();
                    jQuery('#auth-url-link').attr('href', data.auth_url).text(data.auth_url);
                    alert('Please authenticate using the link shown below');
                } else if (data.success) {
                    // Connected successfully
                    setTimeout(refreshStatus, 2000);
                } else {
                    // Error
                    alert('Error connecting: ' + data.message);
                    refreshStatus();
                }
            });
        }

        function disconnectTailscale() {
            if (confirm('Are you sure you want to disconnect from Tailscale?')) {
                jQuery('#status-text').html('Disconnecting from Tailscale...');
                jQuery.post(apiBase + '&action=disconnect', function(data) {
                    if (data.success) {
                        setTimeout(refreshStatus, 2000);
                    } else {
                        alert('Error disconnecting: ' + data.message);
                        refreshStatus();
                    }
                });
            }
        }

        function refreshLogs() {
            jQuery.get(apiBase + '&action=getLogs', function(data) {
                if (data.success) {
                    jQuery('#log-content').text(data.logs || 'No logs available');
                    jQuery('#log-content').scrollTop(jQuery('#log-content')[0].scrollHeight);
                } else {
                    jQuery('#log-content').text('Error loading logs');
                }
            });
        }
        
        // Auto-refresh status every 30 seconds
        setInterval(refreshStatus, 30000);
        
        // Load logs initially
        setTimeout(refreshLogs, 1000);
    </script>
</body>
</html>
