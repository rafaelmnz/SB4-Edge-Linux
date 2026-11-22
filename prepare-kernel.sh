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
# Iris for VA-API (qcom-va-driver): decode-order output, larger capture pools, encoder deblocking controls,
# timestamps on error buffers, NOSHOW recycling (AV1). From qcom-va-driver's patches/ (GPL-2.0); 0006 rebased on 7.4-rc3.
for p in /work/patches/kernel/00{06,07,08,09,10}-*.patch; do $G apply "$p"; done
# ath12k (WCN7850 Wi-Fi): the fw stats counter was never reset after a miss, so every station dump blocked 6 s.
$G apply /work/patches/kernel/0011-wifi-ath12k-reset-the-fw-stats-state-before-every-re.patch
# ath12k: a channel switch (vdev restart) counted the vdev as started again, so every station dump then waited 3 s.
$G apply /work/patches/kernel/0012-wifi-ath12k-don-t-count-a-vdev-restart-as-another-st.patch
$G log --oneline -4
