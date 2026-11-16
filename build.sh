#!/bin/bash
# Builds the Samsung Galaxy Book4 Edge 16" Ubuntu 26.04.1 arm64 ISO from scratch, on an arm64 host with Docker
# (Apple Silicon Mac or arm64 Linux). Output: out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso (+ .sha256).
#   ./build.sh            all steps
#   ./build.sh <step>...  only those steps (image kernel modules usbc ssc fastrpc cryptsetup resources libcamera iso)
set -euo pipefail
cd "$(dirname "$0")"
UBUNTU_ISO=https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-desktop-arm64.iso
mkdir -p out logs iso
run() { docker run --rm -v "$PWD":/work sb4build:latest "$@"; }
krun() { docker run --rm -v sb4-src:/src -v "$PWD":/work sb4build:latest "$@"; }
step() { echo "=== $(date +%T) $1"; }
steps=${*:-image kernel modules usbc ssc fastrpc cryptsetup resources libcamera iso}
for s in $steps; do
	case $s in
	image)      step "build container image sb4build"; docker build -t sb4build:latest docker ;;
	kernel)     step "kernel: v7.4-rc3 + patches/kernel -> out/*.deb"
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
	iso)        step "remaster the Ubuntu ISO"
	            [ -f iso/ubuntu-26.04.1-desktop-arm64.iso ] || curl -fL -o iso/ubuntu-26.04.1-desktop-arm64.iso "$UBUNTU_ISO"
	            docker volume create sb4-iso >/dev/null
	            docker run --rm --privileged -v sb4-iso:/iso -v "$PWD":/work sb4build:latest bash /work/remaster.sh 2>&1 | tee logs/remaster.log ;;
	*) echo "unknown step: $s" >&2; exit 2 ;;
	esac
done
