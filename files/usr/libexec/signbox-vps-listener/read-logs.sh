#!/bin/sh
# Usage: read-logs.sh [lines]

LINES="${1:-200}"

LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"

if [ ! -f "$LOG_FILE" ]; then
	printf 'Log file not found: %s\n' "$LOG_FILE"
	exit 0
fi

tail -n "$LINES" "$LOG_FILE"
