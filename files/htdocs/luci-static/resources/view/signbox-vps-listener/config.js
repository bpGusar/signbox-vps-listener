'use strict';
'require form';
'require fs';
'require ui';

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

return view.extend({
	load: function() {
		return L.resolveDefault(
			fs.read('/var/run/signbox-vps-listener/last_status.json'),
			null
		).then(function(data) {
			this.lastStatus = data;
		}.bind(this));
	},

	render: function() {
		var m, s, o, statusText;

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

		return m.render();
	}
});
