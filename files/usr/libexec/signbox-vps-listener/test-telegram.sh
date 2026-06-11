#!/bin/sh

BOT_TOKEN="$(uci -q get signbox-vps-listener.main.telegram_bot_token)"

if [ -z "$BOT_TOKEN" ]; then
	echo "telegram_bot_token is not configured"
	exit 1
fi

RESPONSE="$(curl -sf --connect-timeout 10 --max-time 20 \
	"https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>&1)" || {
	echo "Failed to reach Telegram API: ${RESPONSE}"
	exit 1
}

case "$RESPONSE" in
	*'"ok":true'*|*'"ok": true'*)
		;;
	*)
		echo "Telegram API error: ${RESPONSE}"
		exit 1
		;;
esac

USERNAME="$(printf '%s' "$RESPONSE" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
FIRST="$(printf '%s' "$RESPONSE" | sed -n 's/.*"first_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

if [ -n "$USERNAME" ]; then
	echo "OK: bot @${USERNAME} is reachable"
elif [ -n "$FIRST" ]; then
	echo "OK: bot \"${FIRST}\" is reachable"
else
	echo "OK: Telegram bot token is valid"
fi

exit 0
