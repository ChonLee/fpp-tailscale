<!--
  Tailscale plugin page. FPP includes this inside its own page (menu.inc wrap=1),
  so it is an HTML fragment: no doctype/html/head/body. JS must work with
  jQuery 3.7 (FPP 7-9) and 4.0 (FPP 10). FPP 7's Bootstrap build lacks most
  utility classes (d-none, small, table-sm...), so layout and show/hide use the
  scoped styles below and jQuery .toggle(), not Bootstrap utilities. Colors
  come from Bootstrap 5.3's CSS variables (in FPP 7-10), so both themes work.
-->
<style>
    #tailscalePlugin .backdrop { margin-bottom: 1rem; }
    #tailscalePlugin .ts-gap { margin-bottom: 0.75rem; }
    #tailscalePlugin .ts-note { font-size: 0.875em; }
    #tailscalePlugin .ts-status {
        padding: 0.75rem 1rem;
        margin-bottom: 0.75rem;
        border: 1px solid;
        border-radius: 0.375rem;
    }
    #tailscalePlugin .ts-status * { color: inherit; }
    #tailscalePlugin .ts-ok {
        color: var(--bs-success-text-emphasis);
        background-color: var(--bs-success-bg-subtle);
        border-color: var(--bs-success-border-subtle);
    }
    #tailscalePlugin .ts-warn {
        color: var(--bs-warning-text-emphasis);
        background-color: var(--bs-warning-bg-subtle);
        border-color: var(--bs-warning-border-subtle);
    }
    #tailscalePlugin .ts-info {
        color: var(--bs-info-text-emphasis);
        background-color: var(--bs-info-bg-subtle);
        border-color: var(--bs-info-border-subtle);
    }
    #tailscalePlugin .ts-muted {
        color: var(--bs-secondary-text-emphasis);
        background-color: var(--bs-secondary-bg-subtle);
        border-color: var(--bs-secondary-border-subtle);
    }
    #tailscalePlugin .ts-error {
        color: var(--bs-danger-text-emphasis);
        background-color: var(--bs-danger-bg-subtle);
        border-color: var(--bs-danger-border-subtle);
    }
    #tailscalePlugin #ts-info { max-width: 40rem; margin-bottom: 0.75rem; }
    #tailscalePlugin #ts-info th,
    #tailscalePlugin #ts-info td { padding: 0.25rem 0.5rem; }
    #tailscalePlugin #ts-info th { width: 35%; }
    #tailscalePlugin #ts-auth-link { word-break: break-all; }
    #tailscalePlugin .ts-check { margin-bottom: 0.5rem; }
    #tailscalePlugin .ts-check label { display: inline-flex; align-items: center; gap: 0.5rem; cursor: pointer; }
    #tailscalePlugin .ts-check input { margin: 0; float: none; }
    #tailscalePlugin label[for="ts-hostname"] { display: block; margin: 0.75rem 0 0.25rem; }
    #tailscalePlugin #ts-hostname { max-width: 20rem; margin-bottom: 0.25rem; }
    #tailscalePlugin .ts-check .ts-note { margin: 0.15rem 0 0 1.75rem; }
    #tailscalePlugin .ts-log {
        max-height: 20rem;
        overflow-y: auto;
        white-space: pre-wrap;
        font-family: monospace;
        font-size: 0.75rem;
        padding: 0.75rem;
        border: 1px solid var(--bs-border-color);
        border-radius: 0.25rem;
        background-color: var(--bs-tertiary-bg);
    }
</style>

<div id="tailscalePlugin">
    <div class="backdrop">
        <h2>Connection</h2>
        <div id="ts-status" class="ts-status ts-muted" role="status">Loading Tailscale status...</div>

        <table id="ts-info" class="table" style="display: none">
            <tbody>
                <tr><th scope="row">Tailscale IP</th><td id="ts-ip"></td></tr>
                <tr><th scope="row">Hostname</th><td id="ts-name"></td></tr>
                <tr><th scope="row">MagicDNS name</th><td id="ts-dns"></td></tr>
                <tr><th scope="row">Tailnet</th><td id="ts-tailnet"></td></tr>
                <tr><th scope="row">Signed in as</th><td id="ts-account"></td></tr>
            </tbody>
        </table>
        <div id="ts-access-note" class="ts-note ts-gap" style="display: none">Every device on this tailnet, and anyone you share this player with, can open FPP's web pages without logging in, the same as someone on your show network. To limit that, use Tailscale's access controls, or turn on a UI password in FPP Settings &rarr; UI.</div>
        <div id="ts-route-warning" class="ts-status ts-error" role="alert" style="display: none"></div>

        <div id="ts-auth" class="ts-gap" style="display: none">
            <a id="ts-auth-link" href="#" target="_blank" rel="noopener"></a>
        </div>

        <div class="ts-gap">
            <button type="button" id="ts-connect" class="buttons btn-success" style="display: none">Connect</button>
            <button type="button" id="ts-disconnect" class="buttons btn-outline-danger" style="display: none">Disconnect</button>
            <button type="button" id="ts-reauth" class="buttons" style="display: none">Force re-authenticate</button>
            <button type="button" id="ts-refresh" class="buttons">Refresh</button>
        </div>
        <div id="ts-message" class="ts-note"></div>
    </div>

    <div class="backdrop">
        <h2>Configuration</h2>
        <div class="ts-check">
            <label><input type="checkbox" class="form-check-input" id="ts-auto-connect"> Auto-connect when FPP starts</label>
        </div>
        <div class="ts-check">
            <label><input type="checkbox" class="form-check-input" id="ts-accept-routes"> Accept subnet routes</label>
            <div class="ts-note">Lets this FPP reach devices on other networks that your Tailscale devices share, such as a controller at another house. Leave it off unless you need that. The plugin won't turn it on if another Tailscale device shares this FPP's own home network, because the FPP would lose its local connection. It only checks when you turn this on and when the FPP connects: if a device starts sharing this FPP's network later, the FPP loses its local connection, including to its controllers, until you turn this off. This page warns you when that happens.</div>
        </div>
        <div class="ts-check">
            <label><input type="checkbox" class="form-check-input" id="ts-auto-update"> Keep Tailscale up to date automatically</label>
            <div class="ts-note">Tailscale installs its own updates from pkgs.tailscale.com when a new version comes out. An update restarts the Tailscale connection for a few seconds; FPP and your show keep running. This is Tailscale's own setting, so the box shows what Tailscale is actually set to, and it can only be changed while Tailscale is running.</div>
        </div>

        <label for="ts-hostname">Device name on your tailnet</label>
        <input type="text" id="ts-hostname" class="form-control" maxlength="63" autocomplete="off">
        <div class="ts-note ts-gap">System hostname: <strong id="ts-system-hostname"></strong>. Leave blank to use it.</div>
        <button type="button" id="ts-save-hostname" class="buttons btn-success">Save name</button>
        <button type="button" id="ts-use-system" class="buttons">Use system hostname</button>
        <div id="ts-config-message" class="ts-note" style="margin-top: 0.5rem"></div>
    </div>

    <div class="backdrop">
        <h2>Recent log</h2>
        <div id="ts-log" class="ts-log ts-gap">Loading...</div>
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
        connected:      { cls: 'ts-ok',   title: 'Connected to Tailscale', buttons: ['disconnect'] },
        needs_auth:     { cls: 'ts-warn',   title: 'Login required', text: 'Click Connect to get a login link.', buttons: ['connect'], fast: true },
        needs_approval: { cls: 'ts-warn',   title: 'Waiting for approval', text: 'Approve this device in the Tailscale admin console.', buttons: ['reauth'], fast: true },
        disconnected:   { cls: 'ts-muted', title: 'Disconnected', text: 'Logged in to Tailscale but not connected.', buttons: ['connect', 'reauth'] },
        starting:       { cls: 'ts-info',      title: 'Connecting...', buttons: ['reauth'], fast: true },
        daemon_down:    { cls: 'ts-muted',    title: 'Tailscale is not running', text: 'Click Connect to start it and sign in.', buttons: ['connect'] },
        not_installed:  { cls: 'ts-error',    title: 'Tailscale is not installed', text: 'Reinstall the plugin from the Plugin Manager to install it.', buttons: [] }
    };

    // api-handler.php refuses POSTs without it (cross-site request forgery).
    var POST_HEADERS = { 'X-Requested-With': 'XMLHttpRequest' };
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

        var $status = $('#ts-status').attr('class', 'ts-status ' + view.cls).empty();
        $status.append($('<strong>').text(view.title));
        if (text) {
            $status.append($('<div class="ts-note">').text(text));
        }

        var connected = status.state === 'connected';
        $('#ts-info').toggle(connected);
        if (connected) {
            $('#ts-ip').text(status.ip || '-');
            $('#ts-name').text(status.hostname || '-');
            $('#ts-dns').text(status.dns_name || '-');
            $('#ts-tailnet').text(status.tailnet || '-');
            $('#ts-account').text(status.account || '-');
        }
        $('#ts-access-note').toggle(connected);

        var conflicts = (connected && status.route_conflicts) || [];
        var $warning = $('#ts-route-warning').toggle(conflicts.length > 0).empty();
        if (conflicts.length) {
            $warning.append($('<strong>').text('Another device now shares this FPP\'s own network'));
            $warning.append($('<div class="ts-note">').text(conflicts.join('; ') + '. While this FPP accepts subnet routes, it can\'t reach devices on its local network, such as its controllers. Turn off Accept subnet routes below.'));
        }

        $('#ts-auth').toggle(hasAuthUrl);
        if (hasAuthUrl) {
            $('#ts-auth-link').attr('href', status.auth_url).text(status.auth_url);
        }

        // With a login link showing, Connect would start a new login and make the
        // link stale, so offer re-auth instead.
        var buttons = hasAuthUrl ? ['reauth'] : view.buttons;
        ['connect', 'disconnect', 'reauth'].forEach(function (name) {
            $('#ts-' + name).toggle(buttons.indexOf(name) !== -1);
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
        $.ajax({ url: API + action, method: 'POST', headers: POST_HEADERS, dataType: 'json' })
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
            headers: POST_HEADERS,
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
            .fail(function (xhr) {
                $('#ts-config-message').text(errorText(xhr));
                // Put checkboxes back to what's actually saved.
                if ('auto_connect' in fields) {
                    $('#ts-auto-connect').prop('checked', !fields.auto_connect);
                }
                if ('accept_routes' in fields) {
                    $('#ts-accept-routes').prop('checked', !fields.accept_routes);
                }
            });
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
                // null: Tailscale isn't running, so its setting can't be read.
                $('#ts-auto-update').prop('checked', data.auto_update === true)
                    .prop('disabled', data.auto_update === null);
                $('#ts-hostname').val(data.config.hostname).attr('placeholder', data.system_hostname);
                $('#ts-system-hostname').text(data.system_hostname);
                render(data.status);
            })
            .fail(function (xhr) {
                $('#ts-status').attr('class', 'ts-status ts-error').text('Could not load status: ' + errorText(xhr));
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
        $('#ts-auto-update').on('change', function () {
            var enabled = this.checked;
            $('#ts-config-message').text('Saving...');
            $.ajax({
                url: API + 'autoUpdate',
                method: 'POST',
                headers: POST_HEADERS,
                contentType: 'application/json',
                data: JSON.stringify({ enabled: enabled }),
                dataType: 'json'
            })
                .done(function (data) {
                    $('#ts-config-message').text('Saved and applied.');
                    $('#ts-auto-update').prop('checked', data.auto_update === true);
                })
                .fail(function (xhr) {
                    $('#ts-config-message').text(errorText(xhr));
                    $('#ts-auto-update').prop('checked', !enabled);
                });
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
