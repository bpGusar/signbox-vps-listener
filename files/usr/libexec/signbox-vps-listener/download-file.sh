#!/bin/sh
# Usage: download-file.sh <url> <dest_path>

URL="$1"
DEST="$2"

[ -n "$URL" ] && [ -n "$DEST" ] || exit 1

DEST_DIR="$(dirname "$DEST")"
mkdir -p "$DEST_DIR" || exit 1

TMP="${DEST}.tmp.$$"
trap 'rm -f "$TMP"' EXIT INT HUP TERM

if ! curl -sfL --connect-timeout 30 --max-time 120 "$URL" -o "$TMP"; then
	exit 1
fi

mv -f "$TMP" "$DEST"
trap - EXIT INT HUP TERM
exit 0
