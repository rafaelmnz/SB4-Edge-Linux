#!/bin/bash
# Build the Galaxy Book4 Edge kernel as .debs.
# Config = Ubuntu 26.04 generic config  ∪  arm64 defconfig (y wins over m)  +  sb4edge.config
set -e
cd /src/linux
export ARCH=arm64 LOCALVERSION=

make defconfig >/dev/null
cp .config /tmp/defconfig.full

python3 - /work/ubuntu-config-7.0.0-30-generic /tmp/defconfig.full .config <<"PY"
import re, sys
def load(p):
    d = {}
    for line in open(p):
        m = re.match(r"^(CONFIG_\w+)=(.*)$", line)
        if m:
            d[m.group(1)] = m.group(2)
    return d
ubuntu, defc = load(sys.argv[1]), load(sys.argv[2])
out = dict(ubuntu)
for k, v in defc.items():
    if v == "y" or (v == "m" and out.get(k) not in ("y", "m")):
        out[k] = v
    elif k not in out:
        out[k] = v
# Ubuntu build-system specifics that do not apply here
for k in ("CONFIG_SYSTEM_TRUSTED_KEYS", "CONFIG_SYSTEM_REVOCATION_KEYS"):
    out[k] = '""'
out["CONFIG_MODULE_SIG_KEY"] = '"certs/signing_key.pem"'  # lockdown selects MODULE_SIG; kernel generates the key
for k in ("CONFIG_MODULE_SIG_ALL", "CONFIG_MODULE_SIG_FORCE", "CONFIG_DEBUG_INFO_BTF", "CONFIG_DEBUG_INFO_DWARF5",
          "CONFIG_DEBUG_INFO_DWARF4", "CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT", "CONFIG_DEBUG_INFO_COMPRESSED_ZLIB",
          "CONFIG_DEBUG_INFO_BTF_MODULES", "CONFIG_DEBUG_INFO"):
    out.pop(k, None)
with open(sys.argv[3], "w") as f:
    for k, v in out.items():
        f.write(f"{k}={v}\n")
print(f"ubuntu={len(ubuntu)} defconfig={len(defc)} merged={len(out)}")
PY

scripts/kconfig/merge_config.sh -m .config /work/sb4edge.config >/dev/null
make olddefconfig >/dev/null
for o in SCSI_UFS_QCOM PHY_QCOM_QMP_UFS ISO9660_FS JOLIET BLK_DEV_SR SCSI_VIRTIO SECURITY_APPARMOR SQUASHFS DRM_MSM ATH12K \
         QCOM_QSEECOM_UEFISECAPP DRM_PANEL_SAMSUNG_ATNA33XC20 I2C_HID_OF BT_HCIUART_QCA EFI_ZBOOT PINCTRL_X1E80100 \
         CLK_X1E80100_GCC INTERCONNECT_QCOM_X1E80100 MODULE_SIG DEBUG_INFO; do
    grep -E "^CONFIG_$o=|# CONFIG_$o is not" .config || echo "MISSING $o"
done
cp .config /work/out/config-sb4edge

make -j14 Image.gz modules dtbs 2>&1 | grep -E "error:|Error [0-9]" | tail -20
make -j1 bindeb-pkg KDEB_PKGVERSION=7.4rc3-2 >/work/logs/deb.log 2>&1
rm -f /work/out/*.deb
mv /src/*.deb /work/out/
ls -la /work/out
