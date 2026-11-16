#!/bin/bash
# libfprint with SDCP for the EgisTec 1c7a:05a1 (ETU905A80-E, egismoc) fingerprint reader. Run in sb4build:
#   docker run --rm -v "$PWD:/work" sb4build bash /work/extra/libfprint/build.sh   -> out/libfprint/*.deb
#
# Without SDCP the sensor keeps no enrolled print: enrollment completes, but the next open lists 0 prints on the
# chip and fprintd deletes the enrollment ("Print was not found on the devices storage"). libfprint MR !547
# ("Implement SDCP v2 (including egismoc implementation)", unmerged) fixes it; n1c0la84 found and tested it on
# the 14" (github.com/n1c0la84/book4-edge-linux). Ubuntu's source package supplies debian/; the source tree is
# replaced with the MR's. The MR tree has no TOD (third-party driver) support, so the TOD packages are dropped,
# along with Ubuntu's patches (egis_etu905 for 05ae/9201 and a goodixmoc fix, made for its 1.95.1+tod1 tree).
set -euxo pipefail
MR_SHA=2d7c5277de08c6b29b3fac7447f17a516fbc4d1c
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get -qq update
apt-get -qq install -y devscripts dpkg-dev curl libssl-dev >/dev/null
mkdir -p /tmp/b && cd /tmp/b
apt-get source libfprint
apt-get -qq build-dep -y libfprint >/dev/null
UB=$(ls -d libfprint-*/)
curl -fsSL -o mr.tar.gz "https://gitlab.freedesktop.org/libfprint/libfprint/-/archive/$MR_SHA/libfprint-$MR_SHA.tar.gz"
tar xzf mr.tar.gz
SRC=libfprint-$MR_SHA
cp -a "$UB/debian" "$SRC/"
cd "$SRC"
# Drop the TOD and doc packages, Ubuntu's patches and the symbols files (the MR tree's ABI is 1.94.10 plus SDCP).
python3 - <<"PY"
import re
p = "debian/control"; s = open(p).read()
paras = s.split("\n\n")
paras = [x for x in paras if not re.search(r"^Package: libfprint-2-(tod|doc)", x, re.M)]
open(p, "w").write("\n\n".join(paras))
PY
rm -f debian/libfprint-2-tod* debian/libfprint-2-doc* debian/*.symbols
rm -rf debian/patches
for p in /work/extra/libfprint/0*.patch; do patch -p1 < "$p"; done
# 3.0 (quilt) wants an orig tarball matching the version; build as native-format binary-only.
echo "3.0 (native)" > debian/source/format
sed -i 's/-Dudev_rules=enabled/-Dudev_rules=enabled -Ddoc=false/' debian/rules
dch --local +sb4edge "libfprint MR !547 ($MR_SHA): SDCP v2 for egismoc, so the EgisTec 1c7a:05a1 keeps enrolled prints. TOD packages and Ubuntu patches dropped."
DEB_BUILD_OPTIONS="nocheck nodoc parallel=14" DEB_BUILD_PROFILES="nodoc" dpkg-buildpackage -us -uc -b -d
mkdir -p /work/out/libfprint && rm -f /work/out/libfprint/*.deb && cp ../*.deb /work/out/libfprint/
ls -la /work/out/libfprint
