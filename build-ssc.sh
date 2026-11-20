#!/bin/sh
# Builds libssc (v0.4.4 + patches/libssc) and iio-sensor-proxy 3.9 (+ patches/iio-sensor-proxy, with SSC support; Ubuntu's 3.8 has none) into
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
rm -rf "$D" /tmp/b1 /tmp/b2 /tmp/src-libssc /tmp/src-iio
# Build from a clean export of each pinned tag (research/ may hold local experiments); every patch must apply.
src() { # src <repo> <tag> <dir> <patch dir>
	mkdir -p "$3"
	git -C "$1" -c safe.directory='*' archive "$2" | tar -x -C "$3"
	for p in "$4"/*.patch; do
		[ -e "$p" ] || continue
		git -C "$3" apply --verbose "$p" || { echo "$p does not apply to $2" >&2; exit 1; }
	done
}
src /work/research/libssc v0.4.4 /tmp/src-libssc /work/patches/libssc
cd /tmp/src-libssc
meson setup /tmp/b1 --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release -Dman=false -Dtests=false >/dev/null 2>&1 || meson setup /tmp/b1 --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release
meson compile -C /tmp/b1 >/dev/null
meson install -C /tmp/b1 --destdir "$D" >/dev/null
meson install -C /tmp/b1 >/dev/null   # for iio-sensor-proxy to find it
# patches/iio-sensor-proxy: client_vanished_cb aborted when a client left while a client table was gone
src /work/research/iio-sensor-proxy 3.9 /tmp/src-iio /work/patches/iio-sensor-proxy
cd /tmp/src-iio
meson setup /tmp/b2 --prefix=/usr --sysconfdir=/etc --libexecdir=libexec --buildtype=release -Dssc-support=enabled -Dgtk-tests=false -Dtests=false -Dgtk_doc=false
meson compile -C /tmp/b2 >/dev/null
meson install -C /tmp/b2 --destdir "$D" >/dev/null
find "$D" -type f | sort
