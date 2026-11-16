# AGENTS.md

Guide for AI coding agents (and people) working on this repository: Linux for the Samsung Galaxy Book4 Edge 16"
(Snapdragon X Elite X1E-84-100), packaged as a remastered Ubuntu 26.04.1 arm64 ISO.

Start here:

1. `ai/KNOWLEDGE.md` - what the hardware needs and how each part was solved, independent of Ubuntu. Read this if you
   want to redo the work another way (Fedora, Arch, NixOS, upstream patches).
2. `docs/DEVELOPMENT-NOTES.md` - the full chronological log, including dead ends and measurements.
3. `README.md` (status, credits), `INSTALL.md` (dual boot with Windows).

A single-file version of all of this plus every text source is attached to each GitHub release as
`sb4edge-ai-bundle.md` (made by `scripts/make-ai-bundle.py`).

## Layout

| Path | What |
|---|---|
| `build.sh` | Orchestrates every step in Docker (`sb4build` image from `docker/`) |
| `prepare-kernel.sh`, `build-kernel.sh`, `patches/kernel/` | Kernel v7.4-rc3 + DT series + local patch |
| `scripts-build-dtbo.sh`, `dtbo/` | Out-of-tree modules and test DT overlays |
| `extra/` | Out-of-tree drivers (EC battery/keyboard, USB-C), rebuilt packages (libcamera, libfprint) |
| `build-*.sh`, `patches/<pkg>/` | Rebuilt Ubuntu packages (cryptsetup, Resources), libssc, fastrpc |
| `overlay/` | Files installed into the image (audio, sensors, backlight, fingerprint, GRUB, udev, services) |
| `remaster.sh` | Builds the ISO from Ubuntu's: installs everything above, sanity-checks the DTB, writes the ISO |
| `refind/` | Boot menu (rEFInd config, theme, GRUB build), `refind/mockup` = design drafts |
| `windows/`, `windows-files/`, `fw/`, `sensors/qcom-root` | Windows-derived firmware/config (third-party, not GPL) |
| `display/`, `fluence/` | EDID tools, VRR test; Qualcomm Fluence (mic noise suppression) tooling and notes |
| `test/` | QEMU harness: install-next-to-Windows test, rEFInd screenshots |
| `tools/`, `dev/scratch/` | Hardware test helpers; one-off development scripts |
| `docs/`, `ai/` | Notes and knowledge base |

## Building and testing

- `./build.sh` (all) or `./build.sh <step>`; needs an arm64 Docker host and ~60 GB. Long steps: run detached.
- `remaster.sh` is read by bash while it runs: never edit it during a build.
- QEMU (`test/qemu-test.sh`, `test/vm/run.sh install|boot`) checks boot and the dual-boot install; it cannot test
  BitLocker, the EC, audio, sensors or the fingerprint reader - those need the laptop.
- `remaster.sh` fails the build if the DTB lacks expected nodes (retimers, keyboard, battery, camera, SD card) or
  if rebuilt packages / PAM settings did not land. Keep those checks when changing things.

## Safety rules on real hardware

- Never write to the Windows partitions or resize them from Linux; Windows is BitLocker-encrypted. Shrink C: in
  Windows only.
- Restarting the ADSP (remoteproc stop/start) or running the sensors domain with a read-only registry can reset
  the whole laptop (TrustZone). Test ADSP changes by reboot.
- Warn the user before any test that may crash or reset the machine.
- Never enroll the same finger in Linux and Windows (each deletes the other's copy); see `ai/KNOWLEDGE.md`.

## Publishing rules

- No personal data in the repository: no names, usernames, passwords, IP addresses, host keys, serial numbers.
  Run `scripts/check-secrets.sh <extra words...>` before every commit meant for GitHub; pass private words as
  arguments, never store them in the repo.
- Windows-derived files stay in their directories with the third-party note in README.md; decompiled Windows code
  is never committed (describe protocols instead).
- Commit messages describe what changed and why; keep `docs/DEVELOPMENT-NOTES.md` and `ai/KNOWLEDGE.md` current
  when a finding changes.
