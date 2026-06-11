#!/bin/sh
set -e

REPO_URL="${REPO_URL:-https://github.com/bpGusar/signbox-vps-listener}"
BRANCH="${BRANCH:-main}"

usage() {
	echo "Usage: $0 [-y|--yes]"
	echo "  -y, --yes   do not ask for confirmation"
	exit 1
}

CONFIRM=0
while [ $# -gt 0 ]; do
	case "$1" in
		-y|--yes)
			CONFIRM=1
			shift
			;;
		-h|--help)
			usage
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			;;
	esac
done

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root" >&2
	exit 1
fi

if [ ! -x /sbin/uci ]; then
	echo "OpenWrt (uci) required" >&2
	exit 1
fi

read_config() {
	LOG_FILE=""
	DOWNLOAD_DIR=""

	if [ -f /etc/config/signbox-vps-listener ]; then
		LOG_FILE="$(uci -q get signbox-vps-listener.main.log_file)"
		DOWNLOAD_DIR="$(uci -q get signbox-vps-listener.main.download_dir)"
	fi

	LOG_FILE="${LOG_FILE:-/var/log/signbox-vps-listener.log}"
}

safe_data_dir() {
	case "$1" in
		""|/|/bin|/dev|/etc|/lib|/lib64|/mnt|/overlay|/proc|/rom|/root|/sbin|/sys|/tmp|/usr|/var|/www)
			return 1
			;;
	esac
	return 0
}

revoke_acl() {
	local idx=0 login

	while login="$(uci -q get rpcd.@login[$idx].username)"; do
		while uci -q del_list "rpcd.@login[$idx].read"='luci-app-signbox-vps-listener' 2>/dev/null; do :; done
		while uci -q del_list "rpcd.@login[$idx].write"='luci-app-signbox-vps-listener' 2>/dev/null; do :; done
		idx=$((idx + 1))
	done

	uci commit rpcd 2>/dev/null || true
}

remove_path() {
	if [ -e "$1" ] || [ -L "$1" ]; then
		rm -rf "$1"
		echo "  removed: $1"
	fi
}

read_config

echo "This will completely remove signbox-vps-listener from the router."
echo "  log file:      ${LOG_FILE}"
if safe_data_dir "$DOWNLOAD_DIR"; then
	echo "  download dir:  ${DOWNLOAD_DIR} (will be deleted)"
else
	echo "  download dir:  ${DOWNLOAD_DIR:-<not set>} (skipped — unsafe or empty path)"
fi
echo

if [ "$CONFIRM" != "1" ]; then
	printf 'Continue? [y/N] '
	read -r ans
	case "$ans" in
		y|Y|yes|YES) ;;
		*) echo "Aborted."; exit 0 ;;
	esac
fi

echo "Stopping service..."
if [ -x /etc/init.d/signbox-vps-listener ]; then
	/etc/init.d/signbox-vps-listener disable 2>/dev/null || true
	/etc/init.d/signbox-vps-listener stop 2>/dev/null || true
fi

# Kill leftover handler/stream if procd did not reap them yet
for pid in $(pgrep -f '/usr/libexec/signbox-vps-listener/' 2>/dev/null); do
	kill "$pid" 2>/dev/null || true
done

echo "Removing files..."

remove_path /etc/init.d/signbox-vps-listener
remove_path /usr/libexec/signbox-vps-listener
remove_path /var/run/signbox-vps-listener
remove_path /var/state/signbox-vps-listener
remove_path /usr/share/luci/menu.d/luci-app-signbox-vps-listener.json
remove_path /usr/share/rpcd/acl.d/luci-app-signbox-vps-listener.json
remove_path /www/luci-static/resources/view/signbox-vps-listener
remove_path /etc/config/signbox-vps-listener

remove_path "$LOG_FILE"
remove_path "${LOG_FILE}.old"
remove_path "${LOG_FILE}.1"

if safe_data_dir "$DOWNLOAD_DIR"; then
	remove_path "$DOWNLOAD_DIR"
fi

# Temp artifacts from stream/handler
for f in /tmp/signbox-vps-listener.* /var/run/signbox-vps-listener/cmd.*.json; do
	remove_path "$f"
done

echo "Revoking LuCI/rpcd ACL..."
revoke_acl

/etc/init.d/rpcd reload 2>/dev/null || true
rm -rf /tmp/luci-* 2>/dev/null || true

echo
echo "Uninstall complete. signbox-vps-listener has been removed."
echo "Note: opkg packages installed by install.sh (curl, ucode, ca-bundle) were not removed."
