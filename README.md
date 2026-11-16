# SB4-Edge-Linux

**Samsung Galaxy Book4 Edge 16" – Linux.** Build scripts for a customised Ubuntu 26.04.1 LTS (arm64) live/installer
ISO for the Samsung Galaxy Book4 Edge 16" (Snapdragon X Elite X1E-84-100), with the kernel, firmware and
userspace pieces this laptop needs.

The ISO itself is not published here (it is 4.8 GB): `build.sh` builds it.

## Hardware status

| Part | Status | Notes |
|---|---|---|
| Display (2880x1800 OLED, 120 Hz) | works | brightness, VRR; brightness remembered across boots |
| Ambient light sensor | works | automatic screen brightness (GNOME) and keyboard backlight (off above 100 lux, on below 50 lux, like Windows) |
| Keyboard, touchpad | works | keyboard backlight remembered across boots |
| Wi-Fi 7 (WCN7850), Bluetooth | works | |
| Speakers (4x WSA883x), headphone jack | works | |
| Microphones | works | Qualcomm Fluence noise suppression on the ADSP |
| Camera (OV02C10) | works | libcamera with an OV02C10 sensor helper |
| USB-C (both ports) | works | SuperSpeed in both orientations, DisplayPort alt mode, charging |
| USB-A | works | SuperSpeed |
| HDMI | works | |
| SD card reader | works | |
| Battery, charging, fan profiles | works | |
| Windows (BitLocker) partitions | works | opened in Files with the BitLocker password or recovery key |
| Fingerprint reader | detected | not tested |

Known issues: switching a USB-C port from DisplayPort back to USB 3 can fail until reboot; Secure Boot must be off
(the kernel is not signed). The 14" model shares most of the devicetree but is untested.

## What is in the image

- **Kernel**: mainline Linux v7.4-rc3 with Maxim Storetvedt's Galaxy Book4 Edge devicetree series and this
  project's changes (`patches/kernel`), packaged as `linux-image-7.4.0-rc3-sb4edge`, wrapped in the stubble EFI
  stub so the devicetree is chosen from the SMBIOS hardware IDs.
- **Out-of-tree drivers** (`extra/`): EC battery and keyboard, USB-C (retimers and PD controller helper).
- **Firmware** from the Windows drivers (`fw/`, `windows-files/`): ADSP/CDSP, Wi-Fi board data, audio modules.
- **Audio** (`overlay/audio`): topology, UCM for the four speakers, microphone setup, Fluence.
- **Ambient light sensor** (`overlay/sensors`): the VEML3328 sits behind the ADSP (Qualcomm Sensor Core); Qualcomm's
  `adsprpcd` serves the sensor registry, `libssc` + iio-sensor-proxy 3.9 read it, GNOME adjusts the screen,
  `sb4edge-kbd-ambient` switches the keyboard backlight.
- **Boot**: rEFInd on the installed system (Linux and Windows), GRUB on the USB stick.
- Rebuilt Ubuntu packages: cryptsetup (BitLocker volumes from recent Windows 11), libcamera (OV02C10), Resources
  (Adreno GPU page).

## Building

Needs an arm64 host with Docker (an Apple Silicon Mac works) and about 60 GB of disk.

```sh
./build.sh            # everything: container image, kernel, drivers, packages, ISO
./build.sh iso        # only the ISO step (after the others have run once)
```

Steps: `image kernel modules usbc ssc fastrpc cryptsetup resources libcamera iso`. The Ubuntu 26.04.1 desktop arm64
ISO is downloaded to `iso/` on the first ISO build. The result is `out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso`.

Write it to a USB drive (e.g. `dd if=out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso of=/dev/rdiskN bs=4m` on macOS),
turn Secure Boot off in the BIOS and boot from it.

## Third-party files

`fw/`, `windows-files/` and `sensors/qcom-root` come from Samsung's and Qualcomm's Windows drivers for this laptop.
They are included so the image can be built, and remain the property of their owners. Upstream sources used:
Linux, quic/fastrpc, libssc, iio-sensor-proxy, rEFInd, Ubuntu.

## License

GPL-2.0 (see `LICENSE`), except the third-party files above.
