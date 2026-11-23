#!/bin/bash
# sb4edge: keep the initramfs from switching to the root file system while plymouth is still bringing up the
# internal panel. With a fast initramfs the switch came ~0.85 s after msm initialized, before plymouth finished its first
# modeset, and plymouth then never showed the splash (screen dark until GDM).
check() { return 0; }
depends() { echo plymouth; }
install() {
    inst_hook pre-pivot 90 "$moddir/sb4edge-splash-wait.sh"
}
