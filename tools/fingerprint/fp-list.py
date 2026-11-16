#!/usr/bin/python3
# Test helper (development): list the prints stored on the fingerprint sensor's chip.
# Run as root with fprintd stopped:  sudo systemctl stop fprintd; sudo G_MESSAGES_DEBUG=all python3 fp-list.py
import gi
gi.require_version('FPrint', '2.0')
from gi.repository import FPrint
ctx = FPrint.Context()
for d in ctx.get_devices():
    print(d.get_name(), d.get_driver(), 'features', d.get_features())
    d.open_sync()
    try:
        prints = d.list_prints_sync()
        print('prints on device:', len(prints))
        for p in prints:
            print(' ', p.get_finger(), p.get_username(), p.get_description(), p.get_enroll_date())
    except Exception as e:
        print('list error', e)
    d.close_sync()
