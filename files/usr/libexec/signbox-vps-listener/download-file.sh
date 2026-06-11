#!/bin/sh
# Usage: download-file.sh <url> <dest_path>

URL="$1"
DEST="$2"
LIBEXEC="/usr/libexec/signbox-vps-listener"

[ -n "$URL" ] && [ -n "$DEST" ] || {
	"$LIBEXEC/log.sh" "download: missing url or destination"
	exit 1
}

DEST_DIR="$(dirname "$DEST")"
mkdir -p "$DEST_DIR" || {
	"$LIBEXEC/log.sh" "download: failed to create directory ${DEST_DIR}"
	exit 1
}

"$LIBEXEC/log.sh" "download: started ${URL} -> ${DEST}"

TMP="${DEST}.tmp.$$"
trap 'rm -f "$TMP"' EXIT INT HUP TERM

if ! curl -sfL --connect-timeout 30 --max-time 120 "$URL" -o "$TMP"; then
	"$LIBEXEC/log.sh" "download: failed ${URL} -> ${DEST}"
	exit 1
fi

mv -f "$TMP" "$DEST"
trap - EXIT INT HUP TERM
"$LIBEXEC/log.sh" "download: completed ${DEST}"
exit 0
