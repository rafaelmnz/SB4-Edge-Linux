FROM ubuntu:26.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends qemu-system-arm qemu-efi-aarch64 ipxe-qemu expect && rm -rf /var/lib/apt/lists/*
