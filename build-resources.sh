#!/bin/bash
# Rebuilds Ubuntu's Resources (GNOME system monitor) with patches/resources/*.patch (Adreno GPU page).
# Run inside sb4build:  docker run --rm -v "$PWD":/work sb4build bash /work/build-resources.sh
# Output: /work/out/resources/*.deb (remaster.sh replaces and holds it if installed).
set -e
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update -qq
apt-get build-dep -y -qq resources >/dev/null
apt-get install -y -qq devscripts quilt >/dev/null
B=/tmp/rs; rm -rf $B; mkdir -p $B; cd $B
apt-get source -qq resources >/dev/null
cd resources-*/
mkdir -p debian/patches; touch debian/patches/series
for p in /work/patches/resources/*.patch; do
  n=sb4edge-$(basename "$p"); cp "$p" debian/patches/$n; echo "$n" >> debian/patches/series
done
QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null
test -f src/devices/gpu/msm.rs
DEBFULLNAME=sb4edge DEBEMAIL=sb4edge@localhost dch -l +sb4edge "GPU page for Qualcomm Adreno (msm) GPUs."
DEB_BUILD_OPTIONS="nocheck nodoc parallel=$(nproc)" dpkg-buildpackage -b -uc -us >/tmp/rs.log 2>&1 || { grep -E "^error|^warning: unused" -A6 /tmp/rs.log | head -60; tail -30 /tmp/rs.log; exit 1; }
mkdir -p /work/out/resources; rm -f /work/out/resources/*.deb
cp ../resources_*.deb /work/out/resources/
ls -l /work/out/resources
