#!/bin/sh

VPS_URL="$(uci -q get signbox-vps-listener.main.vps_url)"
VPS_TOKEN="$(uci -q get signbox-vps-listener.main.vps_token)"

if [ -z "$VPS_URL" ]; then
	echo "vps_url is not configured"
	exit 1
fi

if curl -sfN --connect-timeout 10 --max-time 8 \
	-H "Authorization: Bearer ${VPS_TOKEN}" \
	-H "Accept: text/event-stream" \
	"$VPS_URL" -o /dev/null 2>/dev/null; then
	echo "OK: VPS SSE stream is reachable"
	exit 0
fi

HTTP_CODE="$(curl -sf --connect-timeout 10 --max-time 15 \
	-H "Authorization: Bearer ${VPS_TOKEN}" \
	-H "Accept: text/event-stream" \
	-o /dev/null -w '%{http_code}' "$VPS_URL" 2>/dev/null)" || HTTP_CODE="000"

case "$HTTP_CODE" in
	200|204)
		echo "OK: VPS responded with HTTP ${HTTP_CODE}"
		exit 0
		;;
	401|403)
		echo "VPS reachable but auth failed (HTTP ${HTTP_CODE})"
		exit 1
		;;
	*)
		echo "Failed to connect to VPS (HTTP ${HTTP_CODE:-error})"
		exit 1
		;;
esac
