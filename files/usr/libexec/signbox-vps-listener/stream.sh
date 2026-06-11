#!/bin/sh

LIBEXEC="/usr/libexec/signbox-vps-listener"
RUN_DIR="/var/run/signbox-vps-listener"
CONNECTED_FILE="${RUN_DIR}/connected"
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
		rm -f "$CONNECTED_FILE"
		exit 0
	fi

	if [ -z "$VPS_URL" ]; then
		logger -t signbox-vps-listener "vps_url is not configured"
		sleep "$RECONNECT_DELAY"
		continue
	fi

	date '+%s' > "$CONNECTED_FILE"

	# shellcheck disable=SC2086
	curl -sfN --retry 0 --connect-timeout 30 --max-time 0 \
		-H "Authorization: Bearer ${VPS_TOKEN}" \
		-H "Accept: text/event-stream" \
		"$VPS_URL" 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			data:*)
				json="${line#data:}"
				json="${json#"${json%%[![:space:]]*}"}"
				[ -z "$json" ] && continue

				tmpfile="${RUN_DIR}/cmd.$$.$RANDOM.json"
				printf '%s' "$json" > "$tmpfile"
				ucode "$LIBEXEC/handle-command.uc" "$tmpfile"
				rm -f "$tmpfile"
				;;
			:*) ;;
			'') ;;
		esac
	done

	rm -f "$CONNECTED_FILE"
	logger -t signbox-vps-listener "SSE connection lost, reconnecting in ${RECONNECT_DELAY}s"
	sleep "$RECONNECT_DELAY"
done
