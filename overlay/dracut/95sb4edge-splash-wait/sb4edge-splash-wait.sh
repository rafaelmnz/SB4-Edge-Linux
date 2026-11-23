#!/bin/sh
# Wait (at most ~2.5 s) until a running plymouth has lit the internal panel (eDP connector "enabled").
[ -e /run/plymouth/pid ] || return 0 2>/dev/null || exit 0
i=0
while [ $i -lt 50 ]; do
    for e in /sys/class/drm/card*-eDP-*/enabled; do
        [ -r "$e" ] && [ "$(cat "$e")" = enabled ] && { i=99; break; }
    done
    [ $i -ge 99 ] && break
    sleep 0.05; i=$((i + 1))
done
