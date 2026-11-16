#!/bin/bash
# Rebuilds GNOME Settings (gnome-control-center) and gnome-settings-daemon with patches/<package>/*.patch:
#   gnome-control-center: rename an enrolled fingerprint (Windows Hello imports are numbered, not named); the
#                         automatic-brightness mode row in Power
#   gnome-settings-daemon: automatic-brightness modes (around the slider +-25 %, or a fixed light curve)
# Run inside sb4build:  docker run --rm -v "$PWD":/work sb4build bash /work/build-gnome.sh
# Output: /work/out/gnome/*.deb (remaster.sh replaces the installed ones). On the installed system,
# sb4edge-gnome-rebuild (overlay/gnome-rebuild) redoes this after every GNOME update from the archive.
set -e
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/*.sources
apt-get update -qq
mkdir -p /work/out/gnome; rm -f /work/out/gnome/*.deb
for SRC in gnome-settings-daemon gnome-control-center; do
  apt-get build-dep -y -qq "$SRC" >/dev/null
  B=/tmp/$SRC; rm -rf $B; mkdir -p $B; cd $B
  apt-get source -qq "$SRC" >/dev/null
  cd "$SRC"-*/
  for p in /work/patches/$SRC/*.patch; do
    cp "$p" debian/patches/; basename "$p" >> debian/patches/series
  done
  QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null
  DEBFULLNAME=SB4-Edge-Linux DEBEMAIL=sb4edge@localhost dch -l +sb4edge "sb4edge patches: $(cd /work/patches/$SRC && echo *.patch)"
  DEB_BUILD_OPTIONS="nocheck nodoc parallel=$(nproc)" dpkg-buildpackage -b -uc -us >/tmp/$SRC.log 2>&1 || { grep -E "error" -A6 /tmp/$SRC.log | head -60; tail -30 /tmp/$SRC.log; exit 1; }
  cp ../*+sb4edge*.deb /work/out/gnome/
  # gnome-control-center build-depends on the gnome-settings-daemon it just built (-dev): install ours first
  [ "$SRC" = gnome-settings-daemon ] && dpkg -i ../gnome-settings-daemon-common_*.deb ../gnome-settings-daemon-dev_*.deb >/dev/null 2>&1 || true
done
ls -l /work/out/gnome
