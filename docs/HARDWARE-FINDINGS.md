<!-- First hardware report from the live USB (2026-11-13), written during development; personal details replaced with placeholders. Many items listed here as broken were fixed later: see the README hardware table and DEVELOPMENT-NOTES.md. -->

# First USB boot, 2026-11-13 (live session, kernel 7.4.0-rc2-sb4edge)

Works: keyboard (with udev rule), Bluetooth (with address service), boot, DTB auto-selection (16"), eDP 2880x1800 + refresh rate, backlight, touchpad, touchscreen,
UFS disk visible (953 GB, read-only check), USB-C (keyboard, RNDIS tether), ADSP/CDSP running.

| Problem | Cause | Fix |
|---|---|---|
| Wi-Fi | ath12k: no board data for 17cb:1107 board-id 0xff in board-2.bin | ship Windows `bdwlan.elf` as `ath12k/WCN7850/hw2.0/board.bin` (remaster.sh) |
| Battery 0% | userspace pd-mapper (protection-domain-mapper) replaces the in-kernel qcom_pd_mapper as servreg locator; has no charger_pd, so battmgr returns EAGAIN | mask pd-mapper.service; also ship battmgr.jsn |
| Bluetooth | WCN7850 BT unconfigured: no public address | sb4edge-bt-addr.service sets a stable address from DMI serials (verified live: 26 devices in scan) |
| Keyboard | works in the kernel (ENE 0CF2:9050, events arrive) but udev input_id tags it ID_INPUT_TABLET_PAD (it also has BTN_0/BTN_1 + ABS_VOLUME), so libinput ignores it | overlay/61-sb4edge-keyboard.rules clears the tablet flags on the event node AND the parent inputN (libinput reads both). Verified live: libinput "keyboard pointer", typing works |
| Audio | snd-x1e80100: wcd938x set_jack -22 | expected (no Samsung topology) |

Do not rmmod/modprobe ath12k live: reload oopses in mhi_queue and wedges qrtr (pd-mapper stuck in D state).
| Fingerprint | Egis sensor not on any enabled USB port (usb_mp limited to port 0) | patches/sb4edge-local/0001: enable usb_mp port 1 + eusb5 repeater; untested |
