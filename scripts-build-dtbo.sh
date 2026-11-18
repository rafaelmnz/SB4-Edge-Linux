#!/bin/bash
# Build extra/ out-of-tree modules against the kernel tree and compile dtbo/*.dts (run in sb4build).
set -e
cd /src/linux
# battery before kbd: kbd calls the battery driver's exported sgb_ec_excmd()
for m in sb4-dtbo samsung-galaxybook-battery samsung-galaxybook-kbd gb4e-typec sb4-cdsp-stats; do rm -rf /tmp/$m; cp -r /work/extra/$m /tmp/$m
  x=; [ $m = samsung-galaxybook-kbd ] && x=KBUILD_EXTRA_SYMBOLS=/tmp/samsung-galaxybook-battery/Module.symvers
  make -s ARCH=arm64 -C /src/linux M=/tmp/$m $x modules
  for k in /tmp/$m/*.ko; do scripts/sign-file sha512 certs/signing_key.pem certs/signing_key.x509 $k; cp $k /work/out/; done; done
for f in /work/dtbo/*.dts; do
  cpp -nostdinc -undef -x assembler-with-cpp -D__DTS__ -I include -I arch/arm64/boot/dts "$f" > /tmp/ov.dts
  dtc -@ -q -I dts -O dtb -o "${f%.dts}.dtbo" /tmp/ov.dts; done
ls -la /work/dtbo
