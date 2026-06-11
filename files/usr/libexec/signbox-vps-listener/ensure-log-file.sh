#!/bin/sh

LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"
LOG_DIR="$(dirname "$LOG_FILE")"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 1
touch "$LOG_FILE" 2>/dev/null || exit 1
chmod 644 "$LOG_FILE" 2>/dev/null || true

printf '%s' "$LOG_FILE"
