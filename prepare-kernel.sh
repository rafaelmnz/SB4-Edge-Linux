#!/bin/bash
# Prepares the kernel tree for build-kernel.sh: mainline v7.4-rc3 + patches/kernel (Maxim Storetvedt's Galaxy Book4
# Edge devicetree series, then this project's changes). Run inside sb4build with the source volume on /src:
#   docker volume create sb4-src
#   docker run --rm -v sb4-src:/src -v "$PWD":/work sb4build bash /work/prepare-kernel.sh
set -euo pipefail
TAG=v7.4-rc3
G="git -c safe.directory=* -c user.name=sb4build -c user.email=build@localhost"
if [ ! -d /src/linux/.git ]; then
	git clone --depth 1 -b "$TAG" https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git /src/linux
fi
cd /src/linux
$G fetch --depth 1 origin tag "$TAG" --no-tags
$G checkout -f -q "$TAG"
$G clean -fdq
$G am -q /work/patches/kernel/000[123]-*.patch
$G apply /work/patches/kernel/0004-sb4edge-local-changes.patch
# Iris (video decoder): timestamp metadata index read one past its array while seeking (UBSAN); not fixed upstream yet.
$G apply /work/patches/kernel/0005-media-iris-wrap-the-timestamp-metadata-index-right-a.patch
$G log --oneline -4
