# Build container: Ubuntu 27.04 "tenacious" arm64. There is no 27.04 container image yet, so start from 26.10 and
# upgrade (the same way the ISO's layers are upgraded in remaster.sh). Userland packages built here (libfprint,
# libcamera, cryptsetup, resources, GNOME, libssc/iio-sensor-proxy, fastrpc) then match the ISO's libraries.
FROM ubuntu:26.10
ARG SUITE=tenacious
ENV DEBIAN_FRONTEND=noninteractive
# arm64 for the development series is only on ports.ubuntu.com (archive.ubuntu.com answers 404).
RUN sed -i -e "s/\bstonking\b/${SUITE}/g" -e "s|http://archive.ubuntu.com/ubuntu/\?|http://ports.ubuntu.com/ubuntu-ports/|; s|http://security.ubuntu.com/ubuntu/\?|http://ports.ubuntu.com/ubuntu-ports/|" /etc/apt/sources.list.d/ubuntu.sources \
    # The 26.10 image already carries stonking-updates/-security builds newer than tenacious has so far (zlib1g,
    # libbz2): keep those pockets too, or -dev packages pinned to the tenacious version cannot be installed.
    && printf 'Types: deb\nURIs: http://ports.ubuntu.com/ubuntu-ports/\nSuites: stonking-updates stonking-security\nComponents: main universe restricted multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' > /etc/apt/sources.list.d/stonking-updates.sources \
    && apt-get update && apt-get -y dist-upgrade \
    && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev libdw-dev dwarves squashfs-tools xorriso systemd-ukify stubble python3-pefile python3-libfdt binutils gawk kmod cpio rsync git ca-certificates \
    debhelper-compat python3 zstd xz-utils lz4 device-tree-compiler curl wget \
    debootstrap ubuntu-keyring mtools dosfstools e2fsprogs fdisk gdisk grub-efi-arm64-bin grub-common \
    devscripts quilt \
    && grep -q "VERSION_CODENAME=${SUITE}" /etc/os-release \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
