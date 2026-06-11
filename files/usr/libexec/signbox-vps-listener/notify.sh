#!/bin/sh
# Usage: notify.sh <message> [chat_id]

MESSAGE="$1"
CHAT_ID="$2"
LIBEXEC="/usr/libexec/signbox-vps-listener"

"$LIBEXEC/log.sh" "$MESSAGE"

BOT_TOKEN="$(uci -q get signbox-vps-listener.main.telegram_bot_token)"

if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
	if ! curl -sf --connect-timeout 10 --max-time 30 \
		"https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
		-d "chat_id=${CHAT_ID}" \
		--data-urlencode "text=${MESSAGE}" >/dev/null 2>&1; then
		TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
		LOG_FILE="$("$LIBEXEC/ensure-log-file.sh" 2>/dev/null)" || {
			LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
			LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"
		}
		printf '[%s] telegram: failed to send message to chat_id=%s\n' \
			"$TIMESTAMP" "$CHAT_ID" >> "$LOG_FILE"
	fi
fi

exit 0
