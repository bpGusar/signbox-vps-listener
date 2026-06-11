#!/bin/sh
# Usage: log.sh <message>
# Write to log file only (no Telegram).

LIBEXEC="/usr/libexec/signbox-vps-listener"
LOG_FILE="$("$LIBEXEC/ensure-log-file.sh" 2>/dev/null)" || {
	LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
	LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"
	LOG_DIR="$(dirname "$LOG_FILE")"
	mkdir -p "$LOG_DIR" 2>/dev/null
}

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

printf '[%s] %s\n' "$TIMESTAMP" "$1" >> "$LOG_FILE"

exit 0
