#!/usr/bin/python3
# Test helper (development): enroll the right index directly through libfprint, with on-screen cues for each touch
# (notify-send to the desktop user), then list the chip's storage, verify, and list again after a reopen.
# Used to prove that without SDCP the sensor forgets prints. Run as root with fprintd stopped:
#   sudo systemctl stop fprintd; sudo DESKTOP_USER=$USER python3 fp-enroll-with-cues.py
import gi, os, pwd, subprocess, sys, datetime
gi.require_version('FPrint', '2.0')
from gi.repository import FPrint, GLib
def n(t, b=''):
    print(datetime.datetime.now().strftime('%T'), 'CUE', t, b, flush=True)
    u = os.environ['DESKTOP_USER']; uid = pwd.getpwnam(u).pw_uid
    subprocess.run(['runuser','-u',u,'--','env',f'XDG_RUNTIME_DIR=/run/user/{uid}',
        f'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus','notify-send','-u','critical','-t','15000',
        '-a','Fingerprint','-h','string:x-canonical-private-synchronous:fp', t, b])
ctx = FPrint.Context()
d = ctx.get_devices()[0]
d.open_sync()
def lst(tag):
    ps = d.list_prints_sync()
    print(tag, 'prints on device:', len(ps), [(p.get_finger(), p.get_username()) for p in ps], flush=True)
    return ps
lst('BEFORE')
stages = d.get_nr_enroll_stages()
t = FPrint.Print.new(d); t.set_finger(FPrint.Finger.RIGHT_INDEX); t.set_username(os.environ['DESKTOP_USER'])
def prog(dev, done, pr, data, err):
    if err: n('↩ LIFT, then TOUCH again', err.message)
    elif done < stages: n(f'✔ {done}/{stages} — LIFT, then TOUCH again')
n('👆 TOUCH the sensor now (right index)', f'Enrollment: {stages} touches')
try:
    p = d.enroll_sync(t, None, prog, None)
    n('✅ Enrolled — LIFT your finger', 'Wait for the next cue')
except Exception as e:
    n('⚠ Enrollment failed', str(e)); print('ENROLL ERR', e); sys.exit(1)
ps = lst('AFTER ENROLL')
GLib.usleep(3000000)
n('👆 TOUCH again to verify')
try:
    ok, m = d.verify_sync(p, None, None, None)
    print('VERIFY', ok, flush=True)
    n('✅ MATCH — lift' if ok else '❌ No match — lift')
except Exception as e:
    print('VERIFY ERR', e, flush=True); n('⚠ Verify error', str(e))
lst('AFTER VERIFY')
d.close_sync()
d.open_sync(); lst('AFTER REOPEN'); d.close_sync()
