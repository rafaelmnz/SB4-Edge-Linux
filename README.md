# SB4-Edge-Linux

**Samsung Galaxy Book4 Edge 16" – Linux.** Build scripts for a customised Ubuntu 26.04.1 LTS (arm64) live/installer
ISO for the Samsung Galaxy Book4 Edge 16" (Snapdragon X Elite X1E-84-100), with the kernel, firmware and
userspace pieces this laptop needs.

## Download

Ready-made ISOs are on the [Releases](https://github.com/rafaelmnz/SB4-Edge-Linux/releases) page, split in parts
because GitHub limits each file to 2 GB. Download every `.part*` file plus `SHA256SUMS`, then join and check:

```sh
cat ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part* > ubuntu-26.04.1-sb4edge-desktop-arm64.iso
shasum -a 256 -c SHA256SUMS      # Linux: sha256sum -c SHA256SUMS
```

(Windows: `copy /b ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part1 + ...part2 + ...part3 ubuntu-26.04.1-sb4edge-desktop-arm64.iso`.)
Or build it yourself with `build.sh` (below).

**Installing next to Windows** (shrink C: in Windows first, BitLocker recovery key, Secure Boot off): see
[INSTALL.md](INSTALL.md).

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
| Fingerprint reader | works | EgisTec 1c7a:05a1 in the power button: GNOME login and lock screen, sudo; prints stay on the sensor (SDCP) and can be shared with Windows Hello |

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
  (Adreno GPU page), libfprint with SDCP (`extra/libfprint`, fingerprint reader).
- **Fingerprint** (`extra/libfprint`): the EgisTec sensor only keeps enrolled prints over SDCP. libfprint MR !547
  adds SDCP to its egismoc driver; this sensor's model certificate arrives with one byte zeroed ("Microsoft
  Cor\\x00oration"), so the patch here finds its CA by key identifier and accepts it only when Microsoft's signature
  verifies on the restored bytes. Fingerprint is enabled for sudo and login (password still works).
  Prints live on the chip and are shared with Windows: fingers enrolled in Windows Hello are picked up for Linux
  login at every boot and login (`overlay/fingerprint/sb4edge-fingerprint-import`, single-user systems); enrolling
  the same finger in both makes each system delete the other's copy (see [INSTALL.md](INSTALL.md)).

## Building

Needs an arm64 host with Docker (an Apple Silicon Mac works) and about 60 GB of disk.

```sh
./build.sh            # everything: container image, kernel, drivers, packages, ISO
./build.sh iso        # only the ISO step (after the others have run once)
```

Steps: `image kernel modules usbc ssc fastrpc cryptsetup resources libcamera libfprint iso`. The Ubuntu 26.04.1 desktop arm64
ISO is downloaded to `iso/` on the first ISO build. The result is `out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso`.

Write it to a USB drive (e.g. `dd if=out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso of=/dev/rdiskN bs=4m` on macOS),
turn Secure Boot off in the BIOS and boot from it.

## Third-party files

`fw/`, `windows-files/` and `sensors/qcom-root` come from Samsung's and Qualcomm's Windows drivers for this laptop.
They are included so the image can be built, and remain the property of their owners. Upstream sources used:
Linux, quic/fastrpc, libssc, iio-sensor-proxy, libfprint, rEFInd, Ubuntu.

## Credits and references

This project builds on other people's work on this laptop and on the Snapdragon X platform:

- **Maxim Storetvedt** – Galaxy Book4 Edge devicetree series (v8, patchwork series 1177250), with Kirill A. Korinsky
  and Marcus Glocker: the base of `patches/kernel` (0001–0003).
- **hegjon – [omarchy-galaxy-book4-edge](https://github.com/hegjon/omarchy-galaxy-book4-edge)** (14"): ADSP audio
  topology, four-speaker UCM, WSA883x and PipeWire upmix rules (`overlay/audio`), the USB-C PD helper
  (`extra/usbc`), the Type-C retimer driver (`extra/gb4e-typec`), USB-C devicetree graph and fan curve.
- **Saddytech – [Galaxy-Book4-Edge-linux](https://github.com/Saddytech/Galaxy-Book4-Edge-linux)**: the EC battery
  driver (`extra/samsung-galaxybook-battery`), modified here.
- **ciscobugger – [book4-edge-linux](https://github.com/ciscobugger/book4-edge-linux)** (15.6"): OV02C10 libcamera
  sensor helper and tuning (`extra/libcamera`), EC command notes, DMIC clock reference.
- **Nicola Nicodemo ([n1c0la84](https://github.com/n1c0la84))** – fingerprint reader enablement on the 14" (EgisTec on usb_2)
  and the finding that it needs SDCP ([book4-edge-linux](https://github.com/n1c0la84/book4-edge-linux)).
- **libfprint – [MR !547](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/547)** "Implement SDCP v2
  (including egismoc implementation)": the base of `extra/libfprint`.
- **jglathe – [linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit)** and **[zensanp](https://github.com/zensanp)**'s 6.19 tree – X1E
  devkit Ubuntu images and kernel, idle-state notes
  ([Launchpad bug 2084591](https://bugs.launchpad.net/bugs/2084591)).
- **joshuagrisham – [samsung-galaxybook-extras](https://github.com/joshuagrisham/samsung-galaxybook-extras)**,
  **Maccraft123 – [it8987-qcom-tool](https://github.com/Maccraft123/it8987-qcom-tool)** and **icecream95**'s
  xle-ec-tool: Samsung/EC references.
- **Dylan Van Assche – [libssc](https://codeberg.org/DylanVanAssche/libssc)** and **Bastien Nocera –
  [iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy)**: Qualcomm Sensor Core support
  (ambient light sensor).
- **Qualcomm – [fastrpc](https://github.com/quic/fastrpc)**; **linux-msm –
  [audioreach-topology](https://github.com/linux-msm/audioreach-topology)**,
  [hexagonrpc](https://github.com/linux-msm/hexagonrpc); **AudioReach –
  [audioreach-graphservices](https://github.com/AudioReach/audioreach-graphservices)**.
- **[rEFInd](https://www.rodsbooks.com/refind/)** (Rod Smith), **[stubble](https://github.com/ubuntu/stubble)**,
  **[alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf)**, and the mainline Linux Qualcomm maintainers.

## License

GPL-2.0 (see `LICENSE`), except the third-party files above.
