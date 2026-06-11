#!/bin/sh
# Runs post_action commands from UCI. Writes one JSON object per line to $1.

OUTFILE="$1"
LIBEXEC="/usr/libexec/signbox-vps-listener"

[ -n "$OUTFILE" ] || {
	"$LIBEXEC/log.sh" "post-action: missing output file argument"
	exit 1
}

. /lib/functions.sh

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g' | awk 'BEGIN{ORS="\\n"} {gsub(/\n/,""); print}'
}

config_load signbox-vps-listener
config_get_list actions main post_action

if [ -z "$actions" ]; then
	"$LIBEXEC/log.sh" "post-action: no commands configured"
	: > "$OUTFILE"
	exit 0
fi

action_count=0
for _ in $actions; do
	action_count=$((action_count + 1))
done
"$LIBEXEC/log.sh" "post-action: running ${action_count} command(s)"

: > "${OUTFILE}.tmp"
overall_rc=0

for action in $actions; do
	[ -z "$action" ] && continue

	"$LIBEXEC/log.sh" "post-action: started ${action}"

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

	if [ "$rc" -eq 0 ]; then
		"$LIBEXEC/log.sh" "post-action: completed ${action} (${duration}s)"
	else
		"$LIBEXEC/log.sh" "post-action: failed ${action} (exit ${rc}, ${duration}s)"
		break
	fi
done

mv -f "${OUTFILE}.tmp" "$OUTFILE"

if [ "$overall_rc" -eq 0 ]; then
	"$LIBEXEC/log.sh" "post-action: all commands completed"
else
	"$LIBEXEC/log.sh" "post-action: finished with errors (exit ${overall_rc})"
fi

exit $overall_rc
