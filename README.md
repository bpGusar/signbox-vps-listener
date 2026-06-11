# signbox-vps-listener

## Install

From router (download and run):

```sh
wget -O - https://raw.githubusercontent.com/bpGusar/signbox-vps-listener/main/install.sh | sh
```

From local copy:

```sh
sh install.sh --source /path/to/signbox-vps-listener
```

Configure in LuCI: **Services → Signbox VPS Listener**.

## Uninstall

From router (removes service, config, LuCI UI, logs, runtime state, and download directory):

```sh
wget -O - https://raw.githubusercontent.com/bpGusar/signbox-vps-listener/main/uninstall.sh | sh
```

Non-interactive:

```sh
wget -O - https://raw.githubusercontent.com/bpGusar/signbox-vps-listener/main/uninstall.sh | sh -s -- -y
```

From local copy:

```sh
sh uninstall.sh --yes
```
