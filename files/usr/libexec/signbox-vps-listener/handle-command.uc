#!/usr/bin/ucode
'use strict';

import * as fs from 'fs';
import * as json from 'json';

const LIBEXEC = '/usr/libexec/signbox-vps-listener';
const STATE_DIR = '/var/state/signbox-vps-listener';
const RUN_DIR = '/var/run/signbox-vps-listener';

function popen_read(cmd) {
	let p = fs.popen(cmd, 'r');
	let data = p.read('all');
	p.close();
	return type(data) == 'string' ? data : '';
}

function trim(s) {
	return replace(`${s}`, /^\s+|\s+$/g, '');
}

function uci_get(key) {
	return trim(popen_read(`uci -q get signbox-vps-listener.main.${key} 2>/dev/null`));
}

function basename_url(url) {
	let path = replace(`${url}`, /\?.*$/, '');
	let m = match(path, /\/([^\/]+)$/);
	return m ? m[1] : '';
}

function safe_basename(name) {
	if (!name || length(name) == 0)
		return null;
	if (match(name, /\.\./) || match(name, /[\/\\]/))
		return null;
	return name;
}

function shellquote(s) {
	return `'${replace(`${s}`, /'/g, `'\\''`)}'`;
}

function read_text(path) {
	try {
		let data = fs.read(path);
		return data ? `${data}` : '';
	} catch (e) {
		return '';
	}
}

function write_text(path, data) {
	fs.write(path, `${data}`);
}

function now_iso() {
	let t = trim(popen_read('date -Iseconds 2>/dev/null'));
	return t || trim(popen_read('date'));
}

function get_file_url(entry) {
	if (type(entry) != 'object' || entry == null)
		return '';
	return entry.url ? `${entry.url}` : '';
}

if (length(arg) < 1) {
	warn('handle-command.uc: missing json file argument\n');
	exit(1);
}

let json_path = arg[0];
let raw = read_text(json_path);

if (!raw) {
	warn('handle-command.uc: empty input\n');
	exit(1);
}

let cmd;
try {
	cmd = json(raw);
} catch (e) {
	system(`${LIBEXEC}/notify.sh ${shellquote(`Invalid JSON: ${e}`)}`);
	exit(1);
}

if (cmd.action != 'deploy')
	exit(0);

let cmd_id = cmd.id ? `${cmd.id}` : '';
let chat_id = cmd.chat_id ? `${cmd.chat_id}` : '';
let files = cmd.files;
let steps = [];
let success = true;

if (type(files) != 'array')
	files = [];

system(`mkdir -p ${shellquote(STATE_DIR)} ${shellquote(RUN_DIR)}`);

if (cmd_id) {
	let last_id = trim(read_text(`${STATE_DIR}/last_id`));
	if (last_id == cmd_id)
		exit(0);
}

let download_dir = uci_get('download_dir') || '/etc/signbox';
system(`mkdir -p ${shellquote(download_dir)}`);

for (let i = 0; i < length(files); i++) {
	let url = get_file_url(files[i]);

	if (!url) {
		success = false;
		push(steps, { step: 'download', error: 'missing url', exit_code: 1 });
		break;
	}

	let name = safe_basename(basename_url(url));
	if (!name) {
		success = false;
		push(steps, { step: 'download', url: url, error: 'invalid filename', exit_code: 1 });
		break;
	}

	let dest = `${download_dir}/${name}`;
	let rc = system(`${LIBEXEC}/download-file.sh ${shellquote(url)} ${shellquote(dest)}`);

	push(steps, { step: 'download', url: url, dest: dest, exit_code: rc });

	if (rc != 0) {
		success = false;
		break;
	}
}

if (success) {
	let post_results = `${RUN_DIR}/post_results.${replace(popen_read('date +%s'), /\n/g, '')}`;
	let post_rc = system(`${LIBEXEC}/run-post-actions.sh ${shellquote(post_results)}`);

	let post_raw = trim(read_text(post_results));
	let post_lines = post_raw ? split(post_raw, '\n') : [];

	for (let j = 0; j < length(post_lines); j++) {
		let line = post_lines[j];
		if (!line)
			continue;
		try {
			let step = json(line);
			push(steps, step);
			if (step.exit_code != 0) {
				success = false;
				break;
			}
		} catch (e) {
			success = false;
			push(steps, { step: 'post_action', error: `parse error: ${e}`, exit_code: 1 });
			break;
		}
	}

	system(`rm -f ${shellquote(post_results)}`);

	if (post_rc != 0)
		success = false;
}

let message;

if (success) {
	message = `Deploy ${cmd_id}: OK`;
	for (let k = 0; k < length(steps); k++) {
		let st = steps[k];
		if (st.step == 'download')
			message += `\n  downloaded: ${st.dest}`;
		else if (st.step == 'post_action')
			message += `\n  ${st.command} (exit ${st.exit_code}, ${st.duration})`;
	}
} else {
	message = `Deploy ${cmd_id}: FAILED`;
	for (let k = 0; k < length(steps); k++) {
		let st = steps[k];
		if (st.error)
			message += `\n  error: ${st.error}${st.url ? ` (${st.url})` : ''}`;
		else if (st.step == 'download')
			message += `\n  download failed: ${st.url} -> ${st.dest} (exit ${st.exit_code})`;
		else if (st.step == 'post_action')
			message += `\n  ${st.command} failed (exit ${st.exit_code})\n${st.output || ''}`;
	}
}

let status = {
	id: cmd_id,
	time: now_iso(),
	success: success,
	steps: steps,
};

write_text(`${RUN_DIR}/last_status.json`, json(status));

if (cmd_id)
	write_text(`${STATE_DIR}/last_id`, cmd_id);

if (chat_id)
	system(`${LIBEXEC}/notify.sh ${shellquote(message)} ${shellquote(chat_id)}`);
else
	system(`${LIBEXEC}/notify.sh ${shellquote(message)}`);

exit(success ? 0 : 1);
