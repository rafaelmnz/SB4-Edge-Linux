#!/bin/bash
# Rebuilds Ubuntu's cryptsetup with patches/cryptsetup/*.patch (BitLocker volumes from recent Windows 11 builds).
# Run inside sb4build:  docker run --rm -v "$PWD":/work sb4build bash /work/build-cryptsetup.sh
# Output: /work/out/cryptsetup/*.deb (remaster.sh installs libcryptsetup12 + cryptsetup-bin from there).
set -e
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update -qq
apt-get build-dep -y -qq cryptsetup >/dev/null
apt-get install -y -qq devscripts quilt >/dev/null
B=/tmp/cs; rm -rf $B; mkdir -p $B; cd $B
apt-get source -qq cryptsetup >/dev/null
cd cryptsetup-*/
for p in /work/patches/cryptsetup/*.patch; do
  n=sb4edge-$(basename "$p"); cp "$p" debian/patches/$n; echo "$n" >> debian/patches/series
done
QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null
grep -q "Skipping unknown metadata entry" lib/bitlk/bitlk.c
DEBFULLNAME=sb4edge DEBEMAIL=sb4edge@localhost dch -l +sb4edge "BITLK: skip unknown metadata entries in usable VMKs (Windows 11 clear-key volumes)."
DEB_BUILD_OPTIONS="nocheck nodoc parallel=$(nproc)" dpkg-buildpackage -b -uc -us >/tmp/cs.log 2>&1 || { tail -40 /tmp/cs.log; exit 1; }
mkdir -p /work/out/cryptsetup; rm -f /work/out/cryptsetup/*.deb
cp ../libcryptsetup12_*.deb ../cryptsetup-bin_*.deb ../cryptsetup_*.deb /work/out/cryptsetup/ 2>/dev/null || true
ls -l /work/out/cryptsetup
