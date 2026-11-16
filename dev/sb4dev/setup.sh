#!/bin/sh
# Run at boot by sb4dev.service (dev boots only): SSH with the authorized key, Tailscale with the
# saved identity (same address every boot), then optional local.sh (test modules/overlays).
D=$1
export DEBIAN_FRONTEND=noninteractive
exec >>/run/sb4dev.log 2>&1
set -x
install -d -m700 /var/lib/tailscale && cp -a "$D/tailscale/." /var/lib/tailscale/
dpkg -i "$D"/debs/*.deb
install -d -m700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
install -m600 -o ubuntu -g ubuntu "$D/authorized_keys" /home/ubuntu/.ssh/authorized_keys
systemctl enable --now ssh tailscaled
[ -x "$D/local.sh" ] && "$D/local.sh" "$D"
exit 0
