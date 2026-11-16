#!/bin/sh
# Builds libssc (v0.4.4 + patches/libssc) and iio-sensor-proxy 3.9 (with SSC support; Ubuntu's 3.8 has none) into
# /work/out/ssc/root for remaster.sh (ambient light sensor). Runs inside sb4build (Ubuntu 26.04 arm64):
#   docker run --rm -v "$PWD":/work sb4build:latest sh /work/build-ssc.sh
# Sources: research/libssc (https://codeberg.org/DylanVanAssche/libssc), research/iio-sensor-proxy
# (https://gitlab.freedesktop.org/hadess/iio-sensor-proxy), checked out at those tags with the patch applied.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq meson ninja-build pkg-config gcc libglib2.0-dev libqmi-glib-dev libprotobuf-c-dev protobuf-c-compiler protobuf-compiler python3-dev \
	libgudev-1.0-dev libpolkit-gobject-1-dev libudev-dev systemd-dev udev >/dev/null
# Sources are fetched into research/ (not published) on the first run.
[ -d /work/research/libssc/.git ] || git clone -q https://codeberg.org/DylanVanAssche/libssc.git /work/research/libssc
[ -d /work/research/iio-sensor-proxy/.git ] || git clone -q https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git /work/research/iio-sensor-proxy
D=/work/out/ssc/root
rm -rf "$D" /tmp/b1 /tmp/b2
cd /work/research/libssc
git -c safe.directory='*' checkout -q v0.4.4 -- . 2>/dev/null || true
git -c safe.directory='*' apply --check /work/patches/libssc/*.patch 2>/dev/null && git -c safe.directory='*' apply /work/patches/libssc/*.patch
meson setup /tmp/b1 --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release -Dman=false -Dtests=false >/dev/null 2>&1 || meson setup /tmp/b1 --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release
meson compile -C /tmp/b1 >/dev/null
meson install -C /tmp/b1 --destdir "$D" >/dev/null
meson install -C /tmp/b1 >/dev/null   # for iio-sensor-proxy to find it
cd /work/research/iio-sensor-proxy
git -c safe.directory='*' checkout -q 3.9
meson setup /tmp/b2 --prefix=/usr --sysconfdir=/etc --libexecdir=libexec --buildtype=release -Dssc-support=enabled -Dgtk-tests=false -Dtests=false -Dgtk_doc=false
meson compile -C /tmp/b2 >/dev/null
meson install -C /tmp/b2 --destdir "$D" >/dev/null
find "$D" -type f | sort
