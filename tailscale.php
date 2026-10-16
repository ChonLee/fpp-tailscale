<!--
  Tailscale plugin page. FPP includes this inside its own page (menu.inc wrap=1),
  so it is an HTML fragment: no doctype/html/head/body. Styling comes from FPP's
  Bootstrap 5.3 build; JS must work with jQuery 3.7 (FPP 7-9) and 4.0 (FPP 10).
-->
<style>
    #tailscalePlugin .backdrop { margin-bottom: 1rem; }
    #tailscalePlugin #ts-info { max-width: 40rem; }
    #tailscalePlugin #ts-info th { width: 35%; }
    #tailscalePlugin #ts-auth-link { word-break: break-all; }
    #tailscalePlugin #ts-hostname { max-width: 20rem; }
    #tailscalePlugin .ts-log {
        max-height: 300px;
        overflow-y: auto;
        white-space: pre-wrap;
        font-family: monospace;
        font-size: 12px;
        padding: 0.75rem;
        border: 1px solid var(--bs-border-color, #ccc);
        border-radius: 0.25rem;
        background-color: var(--bs-tertiary-bg, transparent);
    }
</style>

<div id="tailscalePlugin">
    <div class="backdrop">
        <h2>Connection</h2>
        <div id="ts-status" class="alert alert-secondary" role="status">Loading Tailscale status...</div>

        <table id="ts-info" class="table table-sm d-none">
            <tbody>
                <tr><th scope="row">Tailscale IP</th><td id="ts-ip"></td></tr>
                <tr><th scope="row">Hostname</th><td id="ts-name"></td></tr>
                <tr><th scope="row">MagicDNS name</th><td id="ts-dns"></td></tr>
            </tbody>
        </table>

        <div id="ts-auth" class="d-none mb-3">
            <a id="ts-auth-link" href="#" target="_blank" rel="noopener"></a>
        </div>

        <div class="mb-2">
            <button type="button" id="ts-connect" class="buttons btn-success d-none">Connect</button>
            <button type="button" id="ts-disconnect" class="buttons btn-outline-danger d-none">Disconnect</button>
            <button type="button" id="ts-reauth" class="buttons d-none">Force re-authenticate</button>
            <button type="button" id="ts-refresh" class="buttons">Refresh</button>
        </div>
        <div id="ts-message" class="small"></div>
    </div>

    <div class="backdrop">
        <h2>Configuration</h2>
        <div class="form-check">
            <input type="checkbox" class="form-check-input" id="ts-auto-connect">
            <label class="form-check-label" for="ts-auto-connect">Auto-connect when FPP starts</label>
        </div>
        <div class="form-check mb-3">
            <input type="checkbox" class="form-check-input" id="ts-accept-routes">
            <label class="form-check-label" for="ts-accept-routes">Accept subnet routes</label>
        </div>

        <label for="ts-hostname" class="form-label">Device name on your tailnet</label>
        <input type="text" id="ts-hostname" class="form-control mb-1" maxlength="63" autocomplete="off">
        <div class="small mb-2">System hostname: <strong id="ts-system-hostname"></strong>. Leave blank to use it.</div>
        <button type="button" id="ts-save-hostname" class="buttons btn-success">Save name</button>
        <button type="button" id="ts-use-system" class="buttons">Use system hostname</button>
        <div id="ts-config-message" class="small mt-2"></div>
    </div>

    <div class="backdrop">
        <h2>Recent log</h2>
        <div id="ts-log" class="ts-log mb-2">Loading...</div>
        <button type="button" id="ts-refresh-log" class="buttons">Refresh log</button>
    </div>
</div>

<script>
(function ($) {
    'use strict';

    var API = 'plugin.php?plugin=fpp-tailscale&nopage=1&page=api-handler.php&action=';
    var FAST_POLL_MS = 3000;
    var SLOW_POLL_MS = 30000;

    // How each backend state is shown. `fast` polls every 3s, so the page
    // notices a finished login or approval quickly.
    var VIEWS = {
        connected:      { cls: 'alert-success',   title: 'Connected to Tailscale', buttons: ['disconnect'] },
        needs_auth:     { cls: 'alert-warning',   title: 'Login required', text: 'Click Connect to get a login link.', buttons: ['connect'], fast: true },
        needs_approval: { cls: 'alert-warning',   title: 'Waiting for approval', text: 'Approve this device in the Tailscale admin console.', buttons: ['reauth'], fast: true },
        disconnected:   { cls: 'alert-secondary', title: 'Disconnected', text: 'Logged in to Tailscale but not connected.', buttons: ['connect', 'reauth'] },
        starting:       { cls: 'alert-info',      title: 'Connecting...', buttons: ['reauth'], fast: true },
        daemon_down:    { cls: 'alert-danger',    title: 'The Tailscale service is not running', text: 'Connect will try to start it.', buttons: ['connect'] },
        not_installed:  { cls: 'alert-danger',    title: 'Tailscale is not installed', text: 'Reinstall the plugin, or restart FPP to let it reinstall Tailscale.', buttons: [] }
    };

    var pollTimer = null;
    var lastState = null;
    var busy = false;

    function errorText(xhr) {
        if (xhr.responseJSON && xhr.responseJSON.message) {
            return xhr.responseJSON.message;
        }
        return 'Request failed (' + (xhr.status || 'no response') + ')';
    }

    function schedulePoll() {
        clearTimeout(pollTimer);
        if (document.hidden) {
            return;
        }
        var view = VIEWS[lastState];
        pollTimer = setTimeout(poll, view && view.fast ? FAST_POLL_MS : SLOW_POLL_MS);
    }

    function render(status) {
        lastState = status.state;
        var view = VIEWS[status.state] || VIEWS.starting;
        var hasAuthUrl = status.state === 'needs_auth' && /^https:\/\//.test(status.auth_url || '');
        var text = view.text || '';
        if (hasAuthUrl) {
            text = 'Open this link and sign in. This page updates by itself when you are done.';
        } else if (status.state === 'daemon_down' && status.message) {
            text += ' (' + status.message + ')';
        }

        var $status = $('#ts-status').attr('class', 'alert ' + view.cls).empty();
        $status.append($('<strong>').text(view.title));
        if (text) {
            $status.append($('<div class="small">').text(text));
        }

        var connected = status.state === 'connected';
        $('#ts-info').toggleClass('d-none', !connected);
        if (connected) {
            $('#ts-ip').text(status.ip || '-');
            $('#ts-name').text(status.hostname || '-');
            $('#ts-dns').text(status.dns_name || '-');
        }

        $('#ts-auth').toggleClass('d-none', !hasAuthUrl);
        if (hasAuthUrl) {
            $('#ts-auth-link').attr('href', status.auth_url).text(status.auth_url);
        }

        // With a login link showing, Connect would start a new login and make the
        // link stale, so offer re-auth instead.
        var buttons = hasAuthUrl ? ['reauth'] : view.buttons;
        ['connect', 'disconnect', 'reauth'].forEach(function (name) {
            $('#ts-' + name).toggleClass('d-none', buttons.indexOf(name) === -1);
        });

        schedulePoll();
    }

    function poll() {
        if (busy) {
            return schedulePoll();
        }
        $.ajax({ url: API + 'status', dataType: 'json', cache: false })
            .done(function (data) { render(data.status); })
            .fail(function (xhr) {
                $('#ts-message').text(errorText(xhr));
                schedulePoll();
            });
    }

    function setBusy(on, message) {
        busy = on;
        $('#tailscalePlugin button').prop('disabled', on);
        $('#ts-message').text(message || '');
    }

    function runAction(action, workingText, confirmText) {
        if (confirmText && !window.confirm(confirmText)) {
            return;
        }
        setBusy(true, workingText);
        var message = '';
        $.ajax({ url: API + action, method: 'POST', dataType: 'json' })
            .done(function (data) { render(data.status); })
            .fail(function (xhr) {
                message = errorText(xhr);
                if (xhr.responseJSON && xhr.responseJSON.status) {
                    render(xhr.responseJSON.status);
                }
            })
            .always(function () {
                setBusy(false, message);
                loadLog();
            });
    }

    function saveConfig(fields) {
        $('#ts-config-message').text('Saving...');
        $.ajax({
            url: API + 'saveConfig',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify(fields),
            dataType: 'json'
        })
            .done(function (data) {
                $('#ts-config-message').text(data.applied ? 'Saved and applied.' : 'Saved.');
                if (data.applied) {
                    setTimeout(poll, 2000);
                }
            })
            .fail(function (xhr) { $('#ts-config-message').text(errorText(xhr)); });
    }

    function loadLog() {
        $.ajax({ url: API + 'logs', dataType: 'json', cache: false })
            .done(function (data) {
                var $log = $('#ts-log').text(data.logs || 'No log entries yet.');
                $log.scrollTop($log[0].scrollHeight);
            })
            .fail(function (xhr) { $('#ts-log').text(errorText(xhr)); });
    }

    function init() {
        $.ajax({ url: API + 'state', dataType: 'json', cache: false })
            .done(function (data) {
                $('#ts-auto-connect').prop('checked', data.config.auto_connect);
                $('#ts-accept-routes').prop('checked', data.config.accept_routes);
                $('#ts-hostname').val(data.config.hostname).attr('placeholder', data.system_hostname);
                $('#ts-system-hostname').text(data.system_hostname);
                render(data.status);
            })
            .fail(function (xhr) {
                $('#ts-status').attr('class', 'alert alert-danger').text('Could not load status: ' + errorText(xhr));
            });
        loadLog();

        $('#ts-connect').on('click', function () {
            runAction('connect', 'Connecting...');
        });
        $('#ts-disconnect').on('click', function () {
            runAction('disconnect', 'Disconnecting...', 'Disconnect this FPP from Tailscale?');
        });
        $('#ts-reauth').on('click', function () {
            runAction('reauth', 'Logging out and getting a new login link...',
                'This logs the device out of Tailscale and creates a new login link.\n\n' +
                'Use it if the device was removed or expired in the Tailscale admin console. Continue?');
        });
        $('#ts-refresh').on('click', poll);
        $('#ts-refresh-log').on('click', loadLog);

        $('#ts-auto-connect').on('change', function () {
            saveConfig({ auto_connect: this.checked });
        });
        $('#ts-accept-routes').on('change', function () {
            saveConfig({ accept_routes: this.checked });
        });
        $('#ts-save-hostname').on('click', function () {
            saveConfig({ hostname: $('#ts-hostname').val().trim() });
        });
        $('#ts-hostname').on('keydown', function (e) {
            if (e.key === 'Enter') {
                saveConfig({ hostname: $(this).val().trim() });
            }
        });
        $('#ts-use-system').on('click', function () {
            $('#ts-hostname').val('');
            saveConfig({ hostname: '' });
        });

        document.addEventListener('visibilitychange', function () {
            if (document.hidden) {
                clearTimeout(pollTimer);
            } else {
                poll();
            }
        });
    }

    $(init);
})(jQuery);
</script>
