#!/bin/bash
# Rebuild Ubuntu's libcamera with the OV02C10 sensor helper (ciscobugger's patch). Run in sb4build:
#   docker run --rm -v "$PWD:/work" sb4build bash /work/extra/libcamera/build.sh   -> out/libcamera/*.deb
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get -qq update
apt-get -qq install -y devscripts dpkg-dev >/dev/null
mkdir -p /tmp/b && cd /tmp/b
apt-get source libcamera
apt-get -qq build-dep -y libcamera >/dev/null
cd libcamera-*/
# Same change as 0001-ipa-libipa-add-ov02c10-camera-sensor-helper.patch (its context is from a later libcamera),
# inserted in sorted position before the OV2685 helper.
python3 - <<"PY2"
p = "src/ipa/libipa/camera_sensor_helper.cpp"; s = open(p).read()
anchor = "class CameraSensorHelperOv2685 : public CameraSensorHelper\n"
add = """class CameraSensorHelperOv02c10 : public CameraSensorHelper
{
public:
	CameraSensorHelperOv02c10()
	{
		/* From Linux kernel driver: 0x4002/0x4003 = 0x40 at 10bits. */
		blackLevel_ = 4096;
		gain_ = AnalogueGainLinear{ 1, 0, 0, 16 };
	}
};
REGISTER_CAMERA_SENSOR_HELPER("ov02c10", CameraSensorHelperOv02c10)

"""
assert anchor in s and "Ov02c10" not in s
open(p, "w").write(s.replace(anchor, add + anchor, 1))
PY2
# Soft ISP CPU debayer: subtract the black level before the AWB gains / CCM (0.7 applies it after them, which
# scales the pedestal by the red/blue gains: magenta image in dim light on the Book4 Edge OV02C10).
patch -p1 < /work/extra/libcamera/0002-software-isp-subtract-black-level-before-gains.patch
dch --local +sb4edge "Add CameraSensorHelper for OmniVision OV02C10 (Samsung Galaxy Book4 Edge front camera); soft ISP: subtract black level before colour gains."
DEB_BUILD_OPTIONS="nocheck parallel=14" dpkg-buildpackage -us -uc -b
mkdir -p /work/out/libcamera && cp ../*.deb /work/out/libcamera/
ls -la /work/out/libcamera
