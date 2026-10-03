#!/bin/sh
# One-time setup for the Settings > Power charge limit:
#   doas sh ~/.local/src/battery-charge-limit/install.sh
# Installs the helper as root and lets the invoking user run just that
# command without a password (nothing else is allowed).
set -eu
user=${DOAS_USER:-${SUDO_USER:-}}
[ -n "$user" ] || { echo "run this with doas (or sudo)" >&2; exit 1; }
here=$(dirname "$0")

install -o root -g root -m 755 "$here/battery-charge-limit" /usr/local/bin/battery-charge-limit

rule="permit nopass $user as root cmd /usr/local/bin/battery-charge-limit"
if [ -f /etc/doas.conf ]; then
    grep -qxF "$rule" /etc/doas.conf || echo "$rule" >> /etc/doas.conf
    doas -C /etc/doas.conf && echo "doas rule ok"
elif [ -d /etc/sudoers.d ]; then
    echo "$user ALL=(root) NOPASSWD: /usr/local/bin/battery-charge-limit" > /etc/sudoers.d/battery-charge-limit
    chmod 440 /etc/sudoers.d/battery-charge-limit
    echo "sudo rule ok"
fi
echo "installed /usr/local/bin/battery-charge-limit"
