#!/bin/sh
# Wait (at most 2 s) until plymouth has finished lighting the internal panel. The sb4edge msm patch logs
# "sb4edge: intf N AVR" when it enables the panel's display interface; the eDP connector's "enabled" attribute is no
# use here (it already reads "enabled" from the firmware's handover). Reading /dev/kmsg starts at the oldest
# message and then blocks for new ones, so grep returns as soon as the line exists.
[ -e /run/plymouth/pid ] || return 0 2>/dev/null || exit 0
timeout 2 grep -q -m1 "sb4edge: intf .* AVR" /dev/kmsg 2>/dev/null || true
