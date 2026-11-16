#!/bin/bash
# Builds Qualcomm's fastrpc (adsprpcd + libadsprpc) into fluence/fastrpc-build. remaster.sh ships it for the Fluence
# microphone noise suppression (adsprpcd audiopd) and the ambient light sensor (adsprpcd sensorspd).
# Run inside sb4build:  docker run --rm -v "$PWD":/work sb4build bash /work/build-fastrpc.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
REV=89508ea
apt-get update -qq >/dev/null
apt-get install -y -qq autoconf automake libtool pkg-config libyaml-dev libbsd-dev systemd-dev udev >/dev/null
[ -d /work/research/fastrpc/.git ] || git clone -q https://github.com/quic/fastrpc.git /work/research/fastrpc
git -c safe.directory='*' -C /work/research/fastrpc checkout -q "$REV"
# The macOS bind mount refuses exec of autogen.sh: build from a copy.
rm -rf /tmp/fastrpc; cp -r /work/research/fastrpc /tmp/fastrpc; cd /tmp/fastrpc
sh ./autogen.sh >/dev/null
chmod +x configure 2>/dev/null; sh ./configure -q
make -s -j"$(nproc)"
rm -rf /work/fluence/fastrpc-build
make -s install DESTDIR=/work/fluence/fastrpc-build
ls -la /work/fluence/fastrpc-build/usr/local/sbin/adsprpcd
