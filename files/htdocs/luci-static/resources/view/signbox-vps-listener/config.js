'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require poll';

var LOG_POLL_KEY = 'signbox-vps-listener.log_autorefresh';
var LOG_SCRIPT = '/usr/libexec/signbox-vps-listener/read-logs.sh';
var LOG_LINES = '200';
var LOG_POLL_INTERVAL = 2;

function showTestResult(res) {
	var msg = (res.stdout || res.stderr || '').trim();

	if (!msg)
		msg = res.code === 0 ? _('OK') : _('Failed');

	ui.addNotification(
		null,
		E('p', msg),
		res.code === 0 ? 'message' : 'error'
	);
}

function runTest(script) {
	return fs.exec(script, []).then(showTestResult).catch(function(err) {
		ui.addNotification(null, E('p', err.message || String(err)), 'error');
	});
}

function fetchLogs() {
	return fs.exec(LOG_SCRIPT, [ LOG_LINES ]).then(function(res) {
		return (res.stdout || '').trim();
	});
}

function isAutoRefreshEnabled() {
	try {
		var v = localStorage.getItem(LOG_POLL_KEY);
		return v === null || v === '1';
	} catch (e) {
		return true;
	}
}

function setAutoRefreshEnabled(enabled) {
	try {
		localStorage.setItem(LOG_POLL_KEY, enabled ? '1' : '0');
	} catch (e) {}
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(
				fs.read('/var/run/signbox-vps-listener/last_status.json'),
				null
			),
			fetchLogs()
		]).then(function(results) {
			this.lastStatus = results[0];
			this.logText = results[1];
		}.bind(this));
	},

	updateLogField: function(logOption, text) {
		if (!logOption)
			return;

		var ui = logOption.getUIElement && logOption.getUIElement();
		if (ui && ui.setValue)
			ui.setValue(text || _('(no log entries yet)'));
	},

	refreshLogs: function(logOption) {
		return fetchLogs().then(L.bind(function(text) {
			this.logText = text;
			this.updateLogField(logOption, text);
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', err.message || String(err)), 'error');
		});
	},

	setupLogAutoRefresh: function(logOption, autoRefreshOption) {
		var autoUi = autoRefreshOption.getUIElement && autoRefreshOption.getUIElement();

		if (autoUi) {
			autoUi.setValue(isAutoRefreshEnabled() ? '1' : '0');

			if (autoUi.node) {
				autoUi.node.addEventListener('change', function() {
					setAutoRefreshEnabled(autoUi.getValue() === '1');
				});
			}
		}

		this.logPollId = poll.add(L.bind(function() {
			if (!isAutoRefreshEnabled())
				return;

			return this.refreshLogs(logOption);
		}, this), LOG_POLL_INTERVAL);
	},

	remove: function() {
		if (this.logPollId)
			poll.remove(this.logPollId);
	},

	render: function() {
		var m, s, o, statusText, logOption, autoRefreshOption;

		if (this.lastStatus) {
			try {
				var st = JSON.parse(this.lastStatus);
				statusText = (st.success ? 'OK' : 'FAILED') + ' — ' + (st.time || '') + ' — id: ' + (st.id || '-');
			} catch (e) {
				statusText = this.lastStatus;
			}
		} else {
			statusText = _('No deploys yet');
		}

		m = new form.Map(
			'signbox-vps-listener',
			_('Signbox VPS Listener'),
			_('SSE client: receives deploy commands from VPS, downloads files from GitHub raw URLs, runs post-actions.')
		);

		s = m.section(form.NamedSection, 'main', 'signbox-vps-listener', _('Settings'));

		o = s.option(form.Flag, 'enabled', _('Enable service'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'vps_url', _('VPS stream URL'));
		o.placeholder = 'https://vps.example/v1/stream';
		o.rmempty = false;

		o = s.option(form.Value, 'vps_token', _('VPS auth token'));
		o.password = true;
		o.rmempty = false;

		o = s.option(form.Value, 'download_dir', _('Download directory'));
		o.placeholder = '/etc/signbox';
		o.rmempty = false;

		o = s.option(form.Value, 'log_file', _('Log file path'));
		o.placeholder = '/var/log/signbox-vps-listener.log';
		o.rmempty = false;

		o = s.option(form.Value, 'telegram_bot_token', _('Telegram bot token'));
		o.password = true;
		o.optional = true;
		o.rmempty = true;
		o.description = _('Optional. chat_id is sent by VPS in each deploy command.');

		o = s.option(form.DynamicList, 'post_action', _('Post-action commands'));
		o.placeholder = '/etc/init.d/podkop restart';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'signbox-vps-listener', _('Diagnostics'));

		o = s.option(form.DummyValue, '_diag_hint', _('Note'));
		o.default = _('Tests use saved settings. Click Save & Apply first if you changed values above.');

		o = s.option(form.Button, '_test_vps', _('Test VPS connection'));
		o.inputtitle = _('Test VPS');
		o.inputstyle = 'apply';
		o.onclick = function() {
			return runTest('/usr/libexec/signbox-vps-listener/test-vps.sh');
		};

		o = s.option(form.Button, '_test_telegram', _('Test Telegram bot'));
		o.inputtitle = _('Test bot');
		o.inputstyle = 'apply';
		o.description = _('Calls Telegram getMe API with the saved bot token.');
		o.onclick = function() {
			return runTest('/usr/libexec/signbox-vps-listener/test-telegram.sh');
		};

		s = m.section(form.NamedSection, 'main', 'signbox-vps-listener', _('Status'));

		o = s.option(form.DummyValue, '_last_status', _('Last deploy'));
		o.rawhtml = true;
		o.default = statusText.replace(/\n/g, '<br />');

		s = m.section(form.NamedSection, 'main', 'signbox-vps-listener', _('Logs'));

		logOption = s.option(form.TextValue, '_log_view', _('Recent entries'));
		logOption.rows = 18;
		logOption.readonly = true;
		logOption.default = this.logText || _('(no log entries yet)');
		logOption.description = _('Last 200 lines from the configured log file path.');

		autoRefreshOption = s.option(form.Flag, '_auto_refresh_logs', _('Auto-refresh every 2 seconds'));
		autoRefreshOption.default = isAutoRefreshEnabled() ? '1' : '0';
		autoRefreshOption.rmempty = true;
		autoRefreshOption.optional = true;
		autoRefreshOption.write = function() { return true; };
		autoRefreshOption.remove = function() { return true; };
		autoRefreshOption.cfgvalue = function() {
			return isAutoRefreshEnabled() ? '1' : '0';
		};

		o = s.option(form.Button, '_refresh_logs', _('Refresh logs'));
		o.inputtitle = _('Refresh');
		o.inputstyle = 'apply';
		o.onclick = L.bind(function() {
			return this.refreshLogs(logOption);
		}, this);

		return m.render().then(L.bind(function(nodes) {
			this.setupLogAutoRefresh(logOption, autoRefreshOption);
			return nodes;
		}, this));
	}
});
