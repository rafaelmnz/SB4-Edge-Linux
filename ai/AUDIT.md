# Auditing SB4-Edge-Linux (read me first)

This project was developed almost entirely by an AI coding agent (Claude Code) working on real hardware with its
owner, who did the physical tests (touching sensors, plugging cables, booting Windows). Independent review by people
and other AI models is welcome. This file tells a reviewer what the project claims, where the evidence is, and which
parts deserve the closest look.

The single-file bundle `sb4edge-ai-bundle.md` (attached to every GitHub release, rebuilt with
`scripts/make-ai-bundle.py`) contains this file, `AGENTS.md`, `ai/KNOWLEDGE.md`, the development notes, and every
text source of the repository under `### FILE:` headers, followed by a manifest with the SHA-256 of every tracked file
(binaries and omitted files included), so a reviewer can work from one file and still check it against the
repository at the commit named in its header.

## Suggested review tasks

1. **Correctness of claims.** For each item in `ai/KNOWLEDGE.md` marked [verified], check that the code in the bundle
   actually does what the text says. Report contradictions between the notes and the code.
2. **Security review.** Concentrate on the "Security-sensitive parts" below. Each one weakens or touches a security
   boundary on purpose; decide whether the trade-off is sound and whether the implementation is tight.
3. **Hardware safety.** Code that writes to the embedded controller, PD controllers, retimers, the charger, or the
   ADSP. Look for writes outside the documented commands, missing bounds checks, and races.
4. **Kernel patches.** `patches/kernel/0004-sb4edge-local-changes.patch` (devicetree and driver changes) and
   `patches/sb4edge-local/*`. Check devicetree bindings, register values, and whether anything is upstreamable.
5. **Build reproducibility.** `build.sh` and the steps it runs. Inputs are pinned (kernel commit, libfprint MR
   commit, Ubuntu packages by version); report anything fetched unpinned.
6. **Alternative designs.** Where would you solve a problem differently (upstream driver instead of userspace
   helper, another distribution's packaging)? `ai/KNOWLEDGE.md` lists open problems.

## Security-sensitive parts

| Area | File(s) | What to check |
|---|---|---|
| Fingerprint certificate repair | `extra/libfprint/0001-sdcp-model-certificate-verification-fixes.patch` | The sensor's SDCP model certificate has one zeroed byte in its issuer name. The patch restores it only if the CA found by key identifier then verifies the signature over the repaired certificate, and then verifies the CA chain. Is that a sound acceptance rule, or can a forged certificate get through? Is memory handled correctly? |
| SDCP itself | libfprint MR !547 (fetched by `extra/libfprint/build.sh` at a fixed commit) | Unmerged upstream code. Packaged as-is plus the patch above. |
| Fingerprint import | `overlay/fingerprint/sb4edge-fingerprint-import`, `.service`, `.pam-config` | Runs as root at boot and from `pam_exec` at every login session; there it only reports new on-chip prints. A print is bound to a user only by `sudo sb4edge-fingerprint-import` after a touch identifies it among the new prints (chip prints carry no owner). `AUTO_IMPORT=yes` in `/etc/default/sb4edge-fingerprint` restores the touch-free import to the only regular user. Check: the identify step and its timeout, the AUTO_IMPORT parsing and default, file permissions, the `--pam` fork, and the environment it runs in. |
| Fingerprint relabel | `overlay/fingerprint/sb4edge-fingerprint-import --rename`, `org.sb4edge.fingerprint-rename.policy`, `patches/gnome-control-center/sb4edge-fingerprint-rename.patch` | Settings runs the helper through pkexec (auth_admin_keep) to move a print file from one finger to another. Check argument validation (finger names, user name, paths) in the root helper. |
| GNOME rebuild on update | `overlay/gnome-rebuild/*` | An apt hook starts a root service that rebuilds gnome-control-center / gnome-settings-daemon from Ubuntu's deb-src with the patches in `/usr/share/sb4edge/patches` after Ubuntu updates them, so the features survive updates. Check that it only builds Ubuntu sources and local patches and installs only packages already installed. |
| PAM | `remaster.sh` (`pam-auth-update --enable fprintd`, `sb4edge-fingerprint`), `overlay/gnome/sb4edge-gnome-persist` | Fingerprint is accepted for login, the lock screen and sudo (one try, then password). The GDM services are edited by the persist script (token line, pam_fprintd skip in gdm-password). |
| Fingerprint login from the GDM user list | `overlay/fingerprint/sb4edge-fp-identify`, `sb4edge-fp-token`, `sb4edge-gdm-fp-overlay`, `org.sb4edge.FingerprintIdentify.conf`, `overlay/gnome/sb4edge-gnome-persist` | A root D-Bus service (callable by group gdm only) verifies fingers while the greeter's user list is shown and writes a one-time token; `pam_exec sb4edge-fp-token` placed *before* the normal checks in gdm-password and gdm-fingerprint accepts it (`success=done`). Check: token location/permissions/expiry (root 0600, 20 s, whole seconds, consumed once), that only a real fprintd verify-match creates it, the PAM_USER/PAM_SERVICE validation, the D-Bus policy, and the greeter-only resource overlay. gdm-password also skips common-auth's first module (pam_fprintd) via `pam_permit success=1` - check the persist script only adds it while that module really is first. |
| Windows drive unlock / rename / delete | `windows/sb4edge-windows-mount`, `org.sb4edge.windows-write.policy`, `windows/sb4edge-unlock-folder.py` | Root helper run through pkexec (auth_admin). `delete-folder` runs `rm -rf` on the volume: check that only listed unlocked folders on the Windows volume (never its root) are accepted, path normalisation (realpath, relative to the volume), the rename name validation, and the mount handling (bindfs allow_other, alias binds under /run/sb4edge). |
| BitLocker | `INSTALL.md`, `patches/cryptsetup` | Users are told to suspend BitLocker protectors once (`-RebootCount 1`). The cryptsetup patch skips unknown VMK metadata entries; check that it cannot misparse key material. |
| Secure Boot | `README.md`, `INSTALL.md` | Must be off (unsigned kernel). Stated openly; alternatives welcome. |
| Root services | `overlay/**/*.service`, `extra/usbc/usbc.c` | Services that run as root and talk to I2C devices or the EC. |
| Third-party binaries | `fw/`, `windows-files/`, `sensors/qcom-root`, `fluence/` | Firmware and configuration extracted from Samsung/Qualcomm Windows driver packages. Not built here; listed by hash in the manifest. |

## What has been tested, and how

- Tested on one Samsung Galaxy Book4 Edge 16" (X1E-84-100, BIOS P00AKX.068) by its owner, with Windows 11 on the
  same disk. Not tested on the 14" or 15.6" models.
- Tests were physical and manual (touch, listen, plug, measure) and are recorded in `docs/DEVELOPMENT-NOTES.md`
  with the observations (logs, measured values). There is no automated hardware test suite. `hw-check.sh` gathers
  a status report on a running system.
- QEMU (`test/`) covers booting the ISO and installing next to a Windows-like partition layout only.

## Known gaps and honest caveats

- Several fixes are workarounds in userspace for things the firmware does on Windows (USB-C orientation, the charger
  input switch). They work on the tested firmware; a firmware update could change behaviour.
- `[partial]` and `[open]` items in `ai/KNOWLEDGE.md` are not working or not fully working.
- The development notes are a log written during the work. Earlier entries can be superseded by later ones; the
  knowledge base reflects the final state.
- Personal data was removed from published files (names, addresses, serials, host keys). Placeholders such as
  `<lan-ip>` and "the owner" mark the removals.

## Reporting

Open an issue at https://github.com/rafaelmnz/SB4-Edge-Linux/issues. Quote the `### FILE:` path and line, say what
is wrong, and how you would check it on hardware if a test is needed. AI-generated reviews are fine; please say which
model produced them.
