#!/bin/bash
# usage: sudo try.sh <tplg.bin> [channels...] -- installs topology, rebinds the card, records ${DUR:-3} s per channel count from MultiMedia4
F=/lib/firmware/updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin
[ -f /tmp/sb4fr/orig-tplg.bin ] || cp $F /tmp/sb4fr/orig-tplg.bin
cp "$1" $F; shift; CHS="${*:-4 2}"
sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
dmesg -c >/dev/null
echo sound > /sys/bus/platform/drivers/snd-x1e80100/unbind 2>/dev/null; sleep 1
[ -e /sys/bus/platform/devices/sound/driver ] || echo sound > /sys/bus/platform/drivers/snd-x1e80100/bind; sleep 3
PCM=$(grep -m1 "MultiMedia4" /proc/asound/pcm | cut -c4-5 | sed "s/^0//")
amixer -c0 cset name="MultiMedia4 Mixer VA_CODEC_DMA_TX_0" 1 >/dev/null 2>&1
for c in "VA DEC0 MUX=VA_DMIC" "VA DMIC MUX0=DMIC0" "VA_AIF1_CAP Mixer DEC0=1" "VA_DEC0 Volume=${VAVOL:-116}" "VA DEC1 MUX=VA_DMIC" "VA DMIC MUX1=DMIC1" "VA_AIF1_CAP Mixer DEC1=1" "VA_DEC1 Volume=${VAVOL:-116}"; do amixer -c0 cset name="${c%%=*}" "${c#*=}" >/dev/null || echo "cset fail $c"; done
for ch in $CHS; do timeout $(( ${DUR:-3} + 5 )) arecord -D hw:0,$PCM -f S16_LE -r ${RATE:-48000} -c $ch -d ${DUR:-3} /tmp/sb4fr/rec-c$ch.wav >/tmp/sb4fr/arec.log 2>&1; echo "arecord c$ch rc=$? $(tail -1 /tmp/sb4fr/arec.log | cut -c1-80)"; done
dmesg | grep -vE "iommu group|Adding to|Control name|Headset Jack|deferred" | tail -15
