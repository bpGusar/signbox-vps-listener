#!/bin/sh
# Runs post_action commands from UCI. Writes one JSON object per line to $1.

OUTFILE="$1"
[ -n "$OUTFILE" ] || exit 1

. /lib/functions.sh

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g' | awk 'BEGIN{ORS="\\n"} {gsub(/\n/,""); print}'
}

config_load signbox-vps-listener
config_get_list actions main post_action

: > "${OUTFILE}.tmp"
overall_rc=0

for action in $actions; do
	[ -z "$action" ] && continue

	start=$(date +%s)
	output=$(sh -c "$action" 2>&1)
	rc=$?
	end=$(date +%s)
	duration=$((end - start))

	[ "$rc" -ne 0 ] && overall_rc=$rc

	esc_cmd=$(json_escape "$action")
	esc_out=$(json_escape "$output")

	printf '{"step":"post_action","command":"%s","exit_code":%s,"output":"%s","duration":"%ss"}\n' \
		"$esc_cmd" "$rc" "$esc_out" "$duration" >> "${OUTFILE}.tmp"

	[ "$rc" -ne 0 ] && break
done

mv -f "${OUTFILE}.tmp" "$OUTFILE"
exit $overall_rc
