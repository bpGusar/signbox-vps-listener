#!/bin/sh
# Usage: notify.sh <message> [chat_id]

MESSAGE="$1"
CHAT_ID="$2"

LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"

BOT_TOKEN="$(uci -q get signbox-vps-listener.main.telegram_bot_token)"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR" 2>/dev/null

printf '[%s] %s\n' "$TIMESTAMP" "$MESSAGE" >> "$LOG_FILE"

if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
	if ! curl -sf --connect-timeout 10 --max-time 30 \
		"https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
		-d "chat_id=${CHAT_ID}" \
		--data-urlencode "text=${MESSAGE}" >/dev/null 2>&1; then
		printf '[%s] telegram: failed to send message to chat_id=%s\n' \
			"$TIMESTAMP" "$CHAT_ID" >> "$LOG_FILE"
	fi
fi

exit 0
