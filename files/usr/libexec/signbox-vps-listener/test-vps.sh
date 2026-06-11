#!/bin/sh

VPS_URL="$(uci -q get signbox-vps-listener.main.vps_url)"
VPS_TOKEN="$(uci -q get signbox-vps-listener.main.vps_token)"

if [ -z "$VPS_URL" ]; then
	echo "vps_url is not configured"
	exit 1
fi

# SSE keeps the connection open; read headers and bail after a few seconds.
# curl exits 28 on --max-time even after HTTP 200, so do not use -f or || HTTP_CODE=000.
HTTP_CODE="$(curl --connect-timeout 10 --max-time 5 \
	-H "Authorization: Bearer ${VPS_TOKEN}" \
	-H "Accept: text/event-stream" \
	-o /dev/null -w '%{http_code}' \
	"$VPS_URL" 2>/dev/null)" || true

case "$HTTP_CODE" in
	200|204)
		echo "OK: VPS SSE stream is reachable (HTTP ${HTTP_CODE})"
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
