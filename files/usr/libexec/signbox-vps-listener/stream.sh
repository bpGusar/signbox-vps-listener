#!/bin/sh

LIBEXEC="/usr/libexec/signbox-vps-listener"
RUN_DIR="/var/run/signbox-vps-listener"
CONNECTED_FILE="${RUN_DIR}/connected"
CURL_ERR="${RUN_DIR}/curl.err"
RECONNECT_DELAY=5

read_config() {
	ENABLED="$(uci -q get signbox-vps-listener.main.enabled)"
	VPS_URL="$(uci -q get signbox-vps-listener.main.vps_url)"
	VPS_TOKEN="$(uci -q get signbox-vps-listener.main.vps_token)"
}

mkdir -p "$RUN_DIR" /var/state/signbox-vps-listener

while true; do
	read_config

	if [ "$ENABLED" != "1" ]; then
		"$LIBEXEC/log.sh" "service: disabled, stopping stream"
		rm -f "$CONNECTED_FILE"
		exit 0
	fi

	if [ -z "$VPS_URL" ]; then
		"$LIBEXEC/log.sh" "stream: vps_url is not configured"
		sleep "$RECONNECT_DELAY"
		continue
	fi

	"$LIBEXEC/log.sh" "stream: connecting to ${VPS_URL}"

	: > "$CURL_ERR"
	rm -f "${RUN_DIR}/stream_got_data"
	date '+%s' > "$CONNECTED_FILE"

	# shellcheck disable=SC2086
	curl -sfN --retry 0 --connect-timeout 30 --max-time 0 \
		-H "Authorization: Bearer ${VPS_TOKEN}" \
		-H "Accept: text/event-stream" \
		"$VPS_URL" 2>>"$CURL_ERR" | while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			data:*)
				json="${line#data:}"
				json="${json#"${json%%[![:space:]]*}"}"
				[ -z "$json" ] && continue

				if [ ! -f "${RUN_DIR}/stream_got_data" ]; then
					"$LIBEXEC/log.sh" "stream: connected"
					: > "${RUN_DIR}/stream_got_data"
				fi

				"$LIBEXEC/log.sh" "stream: event received (${#json} bytes)"

				tmpfile="${RUN_DIR}/cmd.$$.$RANDOM.json"
				printf '%s' "$json" > "$tmpfile"
				ucode "$LIBEXEC/handle-command.uc" "$tmpfile"
				rc=$?
				rm -f "$tmpfile"

				if [ "$rc" -eq 0 ]; then
					"$LIBEXEC/log.sh" "stream: command handled successfully"
				else
					"$LIBEXEC/log.sh" "stream: command handler failed (exit ${rc})"
				fi
				;;
			:*) ;;
			'') ;;
		esac
	done

	got_data=0
	[ -f "${RUN_DIR}/stream_got_data" ] && got_data=1

	rm -f "$CONNECTED_FILE" "${RUN_DIR}/stream_got_data"

	if [ -s "$CURL_ERR" ]; then
		err_line="$(head -n 1 "$CURL_ERR" | tr -d '\r\n')"
		"$LIBEXEC/log.sh" "stream: connection error: ${err_line:-unknown error}"
	elif [ "$got_data" = "0" ]; then
		"$LIBEXEC/log.sh" "stream: connection closed before receiving data"
	else
		"$LIBEXEC/log.sh" "stream: connection closed"
	fi

	"$LIBEXEC/log.sh" "stream: reconnecting in ${RECONNECT_DELAY}s"
	sleep "$RECONNECT_DELAY"
done
