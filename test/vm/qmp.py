#!/usr/bin/env python3
# qmp.py <socket> shot <out.png> | key <keys...> (e.g. ret, tab, ctrl-alt-f3) | type <text>
import json, socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
def cmd(c, **a):
    f.write(json.dumps({"execute": c, "arguments": a} if a else {"execute": c}) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r: return r
json.loads(f.readline()); cmd("qmp_capabilities")
op = sys.argv[2]
if op == "shot":
    print(cmd("screendump", filename=sys.argv[3], format="png"))
elif op == "key":
    for k in sys.argv[3:]:
        print(cmd("send-key", keys=[{"type": "qcode", "data": x} for x in k.split("-")])); time.sleep(0.3)
elif op == "type":
    m = {" ": "spc", "\n": "ret", "-": "minus", ".": "dot", "/": "slash", "=": "equal", "_": "shift-minus", ":": "shift-semicolon", "|": "shift-backslash", ">": "shift-dot", "'": "apostrophe", '"': "shift-apostrophe", ",": "comma", ";": "semicolon", "*": "shift-8", "&": "shift-7", "$": "shift-4"}
    for ch in sys.argv[3]:
        k = m.get(ch, ("shift-" + ch.lower()) if ch.isupper() else ch)
        cmd("send-key", keys=[{"type": "qcode", "data": x} for x in k.split("-")]); time.sleep(0.05)
