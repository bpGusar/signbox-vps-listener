#!/bin/sh
set -e

REPO_URL="${REPO_URL:-https://github.com/bpGusar/signbox-vps-listener}"
BRANCH="${BRANCH:-main}"
SOURCE=""

usage() {
	echo "Usage: $0 [--source DIR]"
	echo "  --source DIR   install from local directory (default: download from GitHub)"
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--source)
			SOURCE="$2"
			shift 2
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

install_deps() {
	local pkg missing=0
	for pkg in curl ucode ca-bundle; do
		if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
			missing=1
			echo "Installing $pkg..."
			opkg update >/dev/null 2>&1 || true
			opkg install "$pkg" || {
				echo "Failed to install $pkg" >&2
				exit 1
			}
		fi
	done
	[ "$missing" -eq 0 ] || true
}

TMPDIR=""
cleanup() {
	[ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

install_deps

if [ -n "$SOURCE" ]; then
	FILES_DIR="${SOURCE%/}/files"
else
	TMPDIR="$(mktemp -d /tmp/signbox-vps-listener.XXXXXX)"
	echo "Downloading ${REPO_URL} (${BRANCH})..."
	if command -v curl >/dev/null 2>&1; then
		curl -sfL "${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz -C "$TMPDIR"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz -C "$TMPDIR"
	else
		echo "curl or wget required" >&2
		exit 1
	fi
	EXTRACTED=""
	for d in "$TMPDIR"/*; do
		[ -d "$d" ] && EXTRACTED="$d" && break
	done
	FILES_DIR="${EXTRACTED}/files"
fi

if [ ! -d "$FILES_DIR" ]; then
	echo "files/ directory not found in ${SOURCE:-archive}" >&2
	exit 1
fi

FIRST_INSTALL=0
if [ ! -f /etc/config/signbox-vps-listener ]; then
	FIRST_INSTALL=1
fi

echo "Installing files..."
cp -a "$FILES_DIR/etc/init.d/signbox-vps-listener" /etc/init.d/
chmod +x /etc/init.d/signbox-vps-listener

mkdir -p /usr/libexec/signbox-vps-listener
cp -a "$FILES_DIR/usr/libexec/signbox-vps-listener/"* /usr/libexec/signbox-vps-listener/
chmod +x /usr/libexec/signbox-vps-listener/*

mkdir -p /var/run/signbox-vps-listener /var/state/signbox-vps-listener

mkdir -p /usr/share/luci/menu.d
cp -a "$FILES_DIR/usr/share/luci/menu.d/luci-app-signbox-vps-listener.json" /usr/share/luci/menu.d/

mkdir -p /usr/share/rpcd/acl.d
cp -a "$FILES_DIR/usr/share/rpcd/acl.d/luci-app-signbox-vps-listener.json" /usr/share/rpcd/acl.d/

mkdir -p /www/luci-static/resources/view/signbox-vps-listener
cp -a "$FILES_DIR/htdocs/luci-static/resources/view/signbox-vps-listener/config.js" /www/luci-static/resources/view/signbox-vps-listener/

if [ "$FIRST_INSTALL" = "1" ]; then
	cp -a "$FILES_DIR/etc/config/signbox-vps-listener" /etc/config/
else
	echo "Keeping existing /etc/config/signbox-vps-listener"
fi

chmod 600 /etc/config/signbox-vps-listener 2>/dev/null || true

grant_acl() {
	local idx=0 login

	while login="$(uci -q get rpcd.@login[$idx].username)"; do
		if [ "$login" = "root" ] || [ "$login" = "admin" ]; then
			uci -q add_list "rpcd.@login[$idx].read"='luci-app-signbox-vps-listener' 2>/dev/null || true
			uci -q add_list "rpcd.@login[$idx].write"='luci-app-signbox-vps-listener' 2>/dev/null || true
		fi
		idx=$((idx + 1))
	done

	uci commit rpcd 2>/dev/null || true
}

grant_acl

/etc/init.d/rpcd reload 2>/dev/null || true
/etc/init.d/signbox-vps-listener enable
/etc/init.d/signbox-vps-listener restart

rm -rf /tmp/luci-*

echo "Done. Configure in LuCI: Services -> Signbox VPS Listener"
