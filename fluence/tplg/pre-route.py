#!/usr/bin/env python3
"""pre-route.py conf <stream-index>: route mfc -> pre -> custom (m4 quoting makes this awkward inside the route macro)."""
import sys
p, n = sys.argv[1], sys.argv[2]; s = open(p).read()
old = f'"stream{n}.custom1, , stream{n}.mfc1"'
assert s.count(old) == 1
s = s.replace(old, f'"stream{n}.pre1, , stream{n}.mfc1"\n                "stream{n}.custom1, , stream{n}.pre1"')
open(p, "w").write(s); print("routed mfc -> pre -> custom")
