#!/bin/bash
# Builds the Samsung Galaxy Book4 Edge 16" Ubuntu 27.04 arm64 ISO (remastered from 26.10) from scratch, on an arm64 host with Docker
# (Apple Silicon Mac or arm64 Linux). Output: out/ubuntu-27.04-sb4edge-desktop-arm64.iso (+ .sha256).
#   ./build.sh            all steps
#   ./build.sh <step>...  only those steps (image kernel modules usbc ssc fastrpc cryptsetup resources libcamera libfprint gnome iso)
set -euo pipefail
cd "$(dirname "$0")"
UBUNTU_ISO=https://cdimage.ubuntu.com/releases/26.10/release/ubuntu-26.10-desktop-arm64.iso
UBUNTU_ISO_SHA256=9242a38c47eb53a5beb153c249d4843e4366f8955e9b972663e4ab7989311e9f   # Ubuntu's SHA256SUMS for 26.10
# The base ISO is downloaded to a temporary name and only kept when its checksum matches; a cached copy is checked too.
base_iso() {
	local f=iso/ubuntu-26.10-desktop-arm64.iso
	if [ -f "$f" ] && [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" != "$UBUNTU_ISO_SHA256" ]; then
		echo "$f does not match Ubuntu's checksum (interrupted download?): downloading it again" >&2
		rm -f "$f"
	fi
	[ -f "$f" ] && return 0
	curl -fL -o "$f.part" "$UBUNTU_ISO"
	[ "$(shasum -a 256 "$f.part" | cut -d' ' -f1)" = "$UBUNTU_ISO_SHA256" ] ||
		{ echo "downloaded ISO does not match Ubuntu's checksum" >&2; rm -f "$f.part"; return 1; }
	mv "$f.part" "$f"
}
mkdir -p out logs iso
run() { docker run --rm -v "$PWD":/work sb4build:latest "$@"; }
# Kernel and modules: Ubuntu 26.04 container (docker/kernel); the kernel tree's sign-file links libcrypto.so.3.
krun() { docker run --rm -v sb4-src:/src -v "$PWD":/work sb4build:kernel "$@"; }
step() { echo "=== $(date +%T) $1"; }
steps=${*:-image kernel modules usbc ssc fastrpc cryptsetup resources libcamera libfprint gnome iso}
for s in $steps; do
	case $s in
	image)      step "build container images sb4build (27.04) and sb4build:kernel (26.04)"
	            docker build -t sb4build:latest docker
	            docker build -t sb4build:kernel docker/kernel ;;
	kernel)     step "kernel: v7.4-rc4 + patches/kernel -> out/*.deb"
	            docker volume create sb4-src >/dev/null
	            krun bash /work/prepare-kernel.sh
	            krun bash /work/build-kernel.sh ;;
	modules)    step "out-of-tree modules (extra/) and overlays (dtbo/)"; krun bash /work/scripts-build-dtbo.sh ;;
	usbc)       step "USB-C helper (extra/usbc)"
	            run bash -c 'cd /work/extra/usbc && gcc -O2 -Wall -o /work/out/sb4edge-usbc usbc.c' ;;
	ssc)        step "libssc + iio-sensor-proxy (ambient light sensor)"; run sh /work/build-ssc.sh ;;
	fastrpc)    step "Qualcomm fastrpc (adsprpcd)"; run bash /work/build-fastrpc.sh ;;
	cryptsetup) step "cryptsetup (BitLocker)"; run bash /work/build-cryptsetup.sh ;;
	resources)  step "Resources (GPU page)"; run bash /work/build-resources.sh ;;
	libcamera)  step "libcamera (OV02C10)"; run bash /work/extra/libcamera/build.sh ;;
	libfprint)  step "libfprint with SDCP (fingerprint reader)"; run bash /work/extra/libfprint/build.sh ;;
	gnome)      step "GNOME Settings + settings daemon (fingerprint rename, brightness modes)"; run bash /work/build-gnome.sh ;;
	iso)        step "remaster the Ubuntu ISO"
	            base_iso
	            docker volume create sb4-iso >/dev/null
	            docker run --rm --privileged -v sb4-iso:/iso -v "$PWD":/work sb4build:latest bash /work/remaster.sh 2>&1 | tee logs/remaster.log ;;
	*) echo "unknown step: $s" >&2; exit 2 ;;
	esac
done
