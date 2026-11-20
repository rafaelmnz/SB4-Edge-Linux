# SB4-Edge-Linux

**Samsung Galaxy Book4 Edge 16" – Linux.** Build scripts for a customised Ubuntu 27.04 (arm64) live/installer
ISO for the Samsung Galaxy Book4 Edge 16" (Snapdragon X Elite X1E-84-100), with the kernel, firmware and
userspace pieces this laptop needs.

[![Buy me a coffee](https://img.shields.io/badge/buy%20me%20a%20coffee-PayPal-ffdd00?logo=paypal&logoColor=white)](https://paypal.me/rafaelmnz)

## Download

Ready-made ISOs are on the [Releases](https://github.com/rafaelmnz/SB4-Edge-Linux/releases) page, split in parts
because GitHub limits each file to 2 GB. Download every `.part*` file plus `SHA256SUMS`, then join and check:

```sh
cat ubuntu-27.04-sb4edge-desktop-arm64.iso.part* > ubuntu-27.04-sb4edge-desktop-arm64.iso
shasum -a 256 -c SHA256SUMS      # Linux: sha256sum -c SHA256SUMS
```

(Windows: `copy /b ubuntu-27.04-sb4edge-desktop-arm64.iso.part1 + ...part2 + ...part3 ubuntu-27.04-sb4edge-desktop-arm64.iso`.)
Or build it yourself with `build.sh` (below).

**Installing next to Windows** (shrink C: in Windows first, BitLocker recovery key, Secure Boot off): see
[INSTALL.md](INSTALL.md).

## Hardware status

| Part | Status | Notes |
|---|---|---|
| Display (2880x1800 OLED, 120 Hz) | works | brightness, VRR; brightness remembered across boots |
| Ambient light sensor | works | automatic screen brightness (GNOME, with two modes: around the slider or follow room light) and keyboard backlight (off above 100 lux, on below 50 lux, like Windows) |
| Keyboard, touchpad | works | keyboard backlight remembered across boots |
| Touchscreen | works | Goodix (I²C HID), 10 fingers at once |
| Wi-Fi 7 (WCN7850), Bluetooth | works | |
| Speakers (4x WSA883x), headphone jack | works | |
| Microphones | works | Qualcomm Fluence noise suppression on the ADSP |
| Camera (OV02C10) | works | libcamera with an OV02C10 sensor helper |
| USB-C (both ports) | works | SuperSpeed in both orientations, DisplayPort alt mode, charging |
| USB-A | works | SuperSpeed |
| HDMI | works | |
| GPU (Adreno X1-85) | works | OpenGL 4.6, OpenGL ES 3.2, Vulkan 1.4 (Mesa) |
| Video decoding/encoding (Iris) | works | hardware H.264, HEVC, VP9, AV1 decode and H.264/HEVC encode; see [Hardware acceleration](#hardware-acceleration) |
| SD card reader | works | |
| Battery, charging, fan profiles | works | charge limit (GNOME "Preserve battery health") |
| Windows (BitLocker) partitions | works | opened in Files with the BitLocker password or recovery key |
| Fingerprint reader | works | EgisTec 1c7a:05a1 in the power button: GNOME login and lock screen, sudo; prints stay on the sensor (SDCP) and can be shared with Windows Hello; relabel fingers in Settings |

Known issues: switching a USB-C port from DisplayPort back to USB 3 can fail until reboot; Secure Boot must be off
(the kernel is not signed). The 14" model shares most of the devicetree but is untested.

## What is in the image

- **Kernel**: mainline Linux v7.4-rc3 with Maxim Storetvedt's Galaxy Book4 Edge devicetree series and this
  project's changes (`patches/kernel`), packaged as `linux-image-7.4.0-rc3-sb4edge`, wrapped in the stubble EFI
  stub so the devicetree is chosen from the SMBIOS hardware IDs.
- **Out-of-tree drivers** (`extra/`): EC battery and keyboard, USB-C (retimers and PD controller helper).
- **Firmware** from the Windows drivers (`fw/`, `windows-files/`): ADSP/CDSP, GPU, video codec, Wi-Fi board data, audio modules.
- **Audio** (`overlay/audio`): topology, UCM for the four speakers, microphone setup, Fluence.
- **Ambient light sensor** (`overlay/sensors`): the VEML3328 sits behind the ADSP (Qualcomm Sensor Core); Qualcomm's
  `adsprpcd` serves the sensor registry, `libssc` + iio-sensor-proxy 3.9 read it, GNOME adjusts the screen,
  `sb4edge-kbd-ambient` keeps the keyboard backlight at your level in normal light, one step dimmer below 10 lux, off above 40 lux and while the display is off (`/etc/default/sb4edge-kbd-ambient`).
- **Boot**: rEFInd on the installed system (Linux and Windows), GRUB on the USB stick.
- **GNOME** (`patches/gnome-*`): Settings -> Power -> "Brightness Adjustment" chooses how the light sensor sets
  the brightness (up to 25 % around the slider, or a fixed room-light curve the slider shifts); Settings -> Users ->
  Fingerprint can relabel which finger a print is. An apt hook rebuilds both packages with the patches when Ubuntu
  updates them.
- Rebuilt Ubuntu packages: cryptsetup (BitLocker volumes from recent Windows 11), libcamera (OV02C10), Resources
  (Oryon CPU temperature and core count, Adreno GPU monitoring, Hexagon NPU compute DSP load, firmware state and temperature), libfprint with SDCP (`extra/libfprint`, fingerprint reader).
- **Fingerprint** (`extra/libfprint`): the EgisTec sensor only keeps enrolled prints over SDCP. libfprint MR !547
  adds SDCP to its egismoc driver; this sensor's model certificate arrives with one byte zeroed ("Microsoft
  Cor\\x00oration"), so the patch here finds its CA by key identifier and accepts it only when Microsoft's signature
  verifies on the restored bytes. Fingerprint is enabled for sudo and login (password still works).
  Prints live on the chip and are shared with Windows: a finger enrolled in Windows Hello is given to a Linux user
  after that user touches the sensor with it (`overlay/fingerprint/sb4edge-fingerprint-import`; touch-free import
  with `AUTO_IMPORT=yes` in `/etc/default/sb4edge-fingerprint`, single-user systems); enrolling
  the same finger in both makes each system delete the other's copy (see [INSTALL.md](INSTALL.md)).

## Hardware acceleration

**Graphics (Adreno X1-85, Mesa 26.2):** OpenGL 4.6, OpenGL ES 3.2, Vulkan 1.4 (turnip, conformant). GNOME, browsers
and games render on the GPU.

**Video (Iris video engine, kernel `iris` driver):** decoding and encoding are done by a dedicated block, not the GPU,
and are exposed as V4L2 devices (`qcom-iris-decoder`, `qcom-iris-encoder`), not VAAPI.

| Codec | Decode | Encode | Profiles |
|---|---|---|---|
| H.264 | yes | yes | baseline, main, high |
| HEVC (H.265) | yes | yes | main, main 10 |
| VP9 | yes | no | profile 0 (4:2:0 8-bit) |
| AV1 | yes | no | main |

- **GNOME video players and anything GStreamer-based** use it automatically (`v4l2h264dec`, `v4l2h265dec`,
  `v4l2vp9dec`, `v4l2av1dec` outrank the software decoders; encoders `v4l2h264enc`, `v4l2h265enc`).
- **mpv / ffmpeg:** `mpv --hwdec=v4l2m2m-copy`, `ffmpeg -c:v h264_v4l2m2m` (also `hevc_`, `vp9_`).
- **Browsers:** Firefox and Chromium still decode video in software here (their Linux builds expect VAAPI; Firefox's
  V4L2 path is untested).

**Speed** (`tools/video-bench.sh`, on AC power, synthetic moving test pattern; CPU = % of one core, 12 cores = 1200 %):

| Task | Software | CPU | Hardware | CPU |
|---|---|---|---|---|
| Encode H.264 1080p | 183 fps (x264 veryfast) | 580 % | **411 fps** | 49 % |
| Encode H.264 4K | 58 fps (x264 veryfast) | 596 % | **152 fps** | 59 % |
| Encode HEVC 4K | 41 fps (x265 veryfast) | 966 % | **146 fps** | 54 % |
| Decode H.264 1080p | 968 fps | 496 % | 435 fps | **24 %** |
| Decode H.264 4K | 364 fps | 656 % | 167 fps | **29 %** |
| Decode HEVC 4K | 293 fps | 623 % | 245 fps | **41 %** |
| Decode VP9 1080p | 1035 fps | 329 % | 556 fps | **36 %** |
| Decode AV1 1080p | 185 fps (libaom) | 99 % | **429 fps** | 38 % |
| Transcode 4K HEVC → 4K H.264 | 53 fps | 624 % | **98 fps** | 27 % |
| Transcode 4K HEVC → 1080p H.264 | 136 fps | 642 % | **177 fps** | 72 % (scaling on CPU) |

Encoding and transcoding are 1.3-3.5x faster in hardware with a tenth of the CPU. For decoding, the 12-core CPU
can be faster on this easy test content, but hardware decodes every format well above real time (4K at 167-245 fps)
at 3-15 % of the CPU, which is what saves battery and keeps the fans quiet during playback.

## Review and reuse (people and AI models)

This project was developed with an AI coding agent (Claude Code) on real hardware. To review it, or to redo the work
another way (another distribution, upstream patches):

- [`ai/AUDIT.md`](ai/AUDIT.md): what to review, what was tested and how, the security-sensitive parts.
- [`ai/KNOWLEDGE.md`](ai/KNOWLEDGE.md): the hardware facts and how each part was solved, independent of Ubuntu.
- [`AGENTS.md`](AGENTS.md): repository layout, build and safety rules for coding agents.
- **`sb4edge-ai-bundle.md`** on each [release](https://github.com/rafaelmnz/SB4-Edge-Linux/releases): all of the
  above, the development notes and every text source in one file (~800 KB) with a SHA-256 manifest. Give it to an AI
  model as-is. Rebuild it with `scripts/make-ai-bundle.py`.

## Building

Needs an arm64 host with Docker (an Apple Silicon Mac works) and about 60 GB of disk.

```sh
./build.sh            # everything: container image, kernel, drivers, packages, ISO
./build.sh iso        # only the ISO step (after the others have run once)
```

Steps: `image kernel modules usbc ssc fastrpc cryptsetup resources libcamera libfprint gnome iso`. Ubuntu has no
27.04 arm64 desktop ISO, so the Ubuntu 26.10 desktop arm64 ISO is upgraded to 27.04 while remastering. It is downloaded to `iso/` on the first ISO build. The result is `out/ubuntu-27.04-sb4edge-desktop-arm64.iso`.

Write it to a USB drive (e.g. `dd if=out/ubuntu-27.04-sb4edge-desktop-arm64.iso of=/dev/rdiskN bs=4m` on macOS),
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

## Buy me a coffee ☕

If this got Linux running on your Book4 Edge and saved you a few weekends of poking at device trees, you can buy me
a coffee at [paypal.me/rafaelmnz](https://paypal.me/rafaelmnz). Totally optional, but it keeps me going (and the
laptop on Linux)! Bug reports, test results from the 14" and 15.6" and pull requests are just as welcome.

## License

GPL-2.0 (see `LICENSE`), except the third-party files above.
