# Installing SB4-Edge-Linux next to Windows

This installs Ubuntu 26.04.1 (SB4-Edge-Linux) on the internal disk of the Samsung Galaxy Book4 Edge 16", next to
Windows 11. Windows keeps working; a boot menu (rEFInd) lets you choose Ubuntu or Windows at every start.

**The Ubuntu installer cannot resize a BitLocker-encrypted Windows partition**, and on this laptop C: is always
encrypted (BitLocker or Device Encryption). So you make the free space **in Windows first** (step 2), and the
installer only uses that empty space. Nothing on the Windows partitions is changed by Linux.

You need:

- a USB stick or USB SSD of 8 GB or more (everything on it is erased);
- your **BitLocker recovery key** (step 1): you will be asked for it once;
- about an hour.

Back up anything important first. Resizing partitions is safe when done as below, but a backup is always wise.

## 1. In Windows: save the BitLocker recovery key

Turning Secure Boot off and adding a boot menu changes what BitLocker measures at boot, so Windows will ask for the
48-digit recovery key once. Have it before you start:

- it is in your Microsoft account at <https://aka.ms/myrecoverykey> (check that the key ID matches this laptop), or
- open **Terminal (Admin)** and run `manage-bde -protectors -get C:` and write down the "Numerical Password".

Keep it somewhere other than this laptop (phone, paper).

## 2. In Windows: shrink C: to make room for Linux

1. **Turn off Fast Startup**: Control Panel → Hardware and Sound → Power Options → *Choose what the power buttons
   do* → *Change settings that are currently unavailable* → untick **Turn on fast startup** → Save. (With it on,
   Windows never fully shuts down and its partitions stay locked for Linux.)
2. Right-click Start → **Disk Management**.
3. Right-click the **(C:)** partition → **Shrink Volume…**
4. In *Enter the amount of space to shrink in MB*, type the size for Linux. At least **51200** (50 GB);
   **204800** (200 GB) is comfortable. Click **Shrink**.
5. You now have a black bar labelled **Unallocated**. **Leave it like that**: do not create or format a partition
   there; the Ubuntu installer uses it as is.

If Windows offers much less space than you asked for, files it cannot move sit near the end of C:. Open Terminal
(Admin), run `powercfg /h off` (turns off hibernation), restart and try again. You can turn it back on afterwards
with `powercfg /h on`.

Do **not** touch the small partitions (EFI, Recovery) and do not delete anything.

## 3. Make the USB installer

Download the three `.part` files and `SHA256SUMS` from the
[Releases](https://github.com/rafaelmnz/SB4-Edge-Linux/releases) page into one folder, then join and check them.

macOS / Linux (Terminal, in that folder):

```sh
cat ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part* > ubuntu-26.04.1-sb4edge-desktop-arm64.iso
shasum -a 256 -c SHA256SUMS          # Linux: sha256sum -c SHA256SUMS   -> must say OK
```

Windows (Command Prompt, in that folder):

```bat
copy /b ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part1 + ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part2 + ubuntu-26.04.1-sb4edge-desktop-arm64.iso.part3 ubuntu-26.04.1-sb4edge-desktop-arm64.iso
certutil -hashfile ubuntu-26.04.1-sb4edge-desktop-arm64.iso SHA256
```

(compare the result with the hash in `SHA256SUMS`).

Write the ISO to the USB drive:

- **balenaEtcher** (Windows, macOS, Linux): *Flash from file* → the ISO → the USB drive → *Flash*; or
- **Rufus** (Windows): select the ISO, and when asked, choose **Write in DD Image mode**; or
- macOS: `diskutil list` to find the USB disk (e.g. `disk4`, check the size!), then
  `diskutil unmountDisk /dev/disk4 && sudo dd if=ubuntu-26.04.1-sb4edge-desktop-arm64.iso of=/dev/rdisk4 bs=4m`.

## 4. In the BIOS: turn Secure Boot off

The SB4-Edge-Linux kernel is not signed by Microsoft, so Secure Boot must be off (Windows still boots fine with it
off).

1. Shut down. Press the power button and tap **F2** while the Samsung logo shows to open the BIOS setup.
2. Find **Secure Boot Control** (under *Boot*) and set it to **Off**. Save and exit (F10).

## 5. Boot the USB stick

1. Plug in the USB drive. Power on and tap **F10** at the Samsung logo for the boot device menu (or set the USB drive
   first in the BIOS boot order), and pick the USB drive.
2. The live Ubuntu desktop starts. You can try everything first: Wi-Fi, sound, camera, keyboard light, etc.

## 6. Install

1. Double-click **Install Ubuntu** on the desktop (or the icon in the dock) and go through language, keyboard and
   network.
2. At *How do you want to install Ubuntu?* choose **Install Ubuntu alongside Windows Boot Manager**. It puts Ubuntu
   in the unallocated space from step 2 and leaves Windows alone.
   - If that option is missing, choose **Manual installation**, select the **free space** and click **+**: use it all
     as **Ext4**, mount point **/**. Leave the existing EFI partition as it is (*not* formatted), and choose the
     internal disk as *Device for boot loader installation*.
   - **Never choose "Erase disk and install Ubuntu"**: it wipes Windows.
   - Leave the installer's own disk encryption option off (untested on this laptop).
3. Create your user, pick the time zone and let it install. When it finishes, click **Restart now** and remove the USB
   drive when told.

## 7. First boot

- The **rEFInd** boot menu appears with Ubuntu and Windows. Use the arrow keys or touchpad and Enter; Ubuntu starts by
  itself after 5 seconds.
- **The first time you start Windows** from this menu, BitLocker asks for the **recovery key** (step 1). Type it in.
  To stop it asking again, open **Terminal (Admin)** in Windows and run:

  ```bat
  manage-bde -protectors -disable C: -RebootCount 1
  ```

  then restart and choose Windows in rEFInd once more; BitLocker re-seals itself to the new boot path.
- If you turned hibernation off in step 2, you can turn it back on now (`powercfg /h on`). Keep Fast Startup off.

## 8. After installing

- **Fingerprint**: the sensor stores fingerprints on the chip itself, shared by Windows and Linux. A finger enrolled
  in Ubuntu does **not** work in Windows (Windows Hello keeps its own list), but a finger enrolled in Windows can
  work in Ubuntu too. So **enroll your fingers in Windows Hello** (Windows Settings → Accounts → Sign-in options →
  Fingerprint recognition). Ubuntu picks up new Windows fingers by itself at every start-up (before the login
  screen) and at every login, so the next time you are at the Ubuntu login, the same finger unlocks it, the lock
  screen and `sudo` (the password always works too). Rest the finger on the power button, do not press it.
  - **Do not enroll the same finger in Ubuntu's Settings** as well: each system then deletes the other's copy.
    Fingers you only use in Ubuntu can be enrolled in Settings → System → Users → *Fingerprint Login*.
  - The automatic pick-up only runs while Ubuntu has a single user account (so a finger someone enrolled in their
    own Windows account cannot unlock yours). With several accounts, import by hand after enrolling one finger in
    Windows: `sudo sb4edge-fingerprint-import <user> right-index` (`--list` shows what is on the sensor).
- **Windows files**: the Windows partition shows up in Files. If it is locked, click it and type the BitLocker
  recovery key once.
- **Updates**: use Software Updater / `sudo apt upgrade` as usual. A few packages (kernel, libcamera, libfprint,
  cryptsetup, Resources) are SB4-Edge builds and are held/pinned so updates do not replace them. Do not remove those
  holds.

## Removing Linux again

In Windows Disk Management, delete the Linux partition (the one without a drive letter, of the size you made in step
2) and extend C: into the free space. Then remove the boot entries from an admin Terminal: `bcdedit /enum firmware`
lists them; `bcdedit /delete {ID}` removes the ones named *rEFInd* and *ubuntu*. The `EFI\refind` and `EFI\ubuntu` folders left on the EFI partition
are harmless. Turn Secure Boot back on if you like.
