#!/bin/bash
# sudo restore.sh -- puts the ISO's topology back, rebinds the card and restarts PipeWire
cp /tmp/sb4fr/orig-tplg.bin /lib/firmware/updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin
echo sound > /sys/bus/platform/drivers/snd-x1e80100/unbind 2>/dev/null; sleep 1
echo sound > /sys/bus/platform/drivers/snd-x1e80100/bind; sleep 3
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber
