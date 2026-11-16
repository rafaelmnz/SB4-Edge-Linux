FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev libdw-dev dwarves squashfs-tools xorriso systemd-ukify stubble python3-pefile python3-libfdt binutils gawk kmod cpio rsync git ca-certificates \
    debhelper-compat python3 zstd xz-utils lz4 device-tree-compiler curl wget \
    debootstrap ubuntu-keyring mtools dosfstools e2fsprogs fdisk gdisk grub-efi-arm64-bin grub-common \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
