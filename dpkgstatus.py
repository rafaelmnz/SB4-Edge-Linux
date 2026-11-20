#!/usr/bin/env python3
# diff:  dpkgstatus.py diff BEFORE AFTER OUT.json  -> stanzas new/changed in AFTER; a package whose stanza is gone
#        from AFTER (removed by the upgrade, no config files left) is recorded as null
# merge: dpkgstatus.py merge STATUS CHANGED.json [BEFORE] -> apply those stanzas to STATUS
#        With BEFORE (the lower layer's status before the change), a package that was installed in BEFORE but
#        is not installed in STATUS was removed by this layer (e.g. the live layer swaps dracut for
#        initramfs-tools), so its upgraded stanza is skipped: merging it would mark it installed with no files.
#        A null (removed below) drops the package from STATUS when STATUS still has the stanza it inherited from
#        BEFORE; a stanza the upper layer changed itself (its own install of that package) is kept.
import json
import sys


def key(stanza):
    fields = dict(
        line.split(":", 1) for line in stanza.splitlines() if line and not line[0].isspace() and ":" in line
    )
    return fields["Package"].strip() + "|" + fields.get("Architecture", "").strip()


def field(stanza, name):
    for line in stanza.splitlines():
        if line.startswith(name + ":"):
            return line.split(":", 1)[1].strip()
    return None


def parse(path):
    text = open(path, encoding="utf-8").read().strip()
    return {key(s): s for s in text.split("\n\n") if s.strip()}


def write(path, stanzas):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n\n".join(stanzas[k] for k in sorted(stanzas)) + "\n")


if sys.argv[1] == "diff":
    before, after = parse(sys.argv[2]), parse(sys.argv[3])
    # apt rewrites Priority/Section from the repo index; only new packages or
    # version/state changes matter for the upper layers.
    changed = {
        k: v
        for k, v in after.items()
        if k not in before
        or any(field(before[k], f) != field(v, f) for f in ("Version", "Status"))
    }
    gone = sorted(k for k in before if k not in after)
    changed.update({k: None for k in gone})
    json.dump(changed, open(sys.argv[4], "w"))
    print(len(changed) - len(gone), "changed/new packages:",
          " ".join(sorted(k.split("|")[0] for k in changed if changed[k] is not None)))
    if gone:
        print(len(gone), "removed packages:", " ".join(k.split("|")[0] for k in gone))
elif sys.argv[1] == "merge":
    status = parse(sys.argv[2])
    changed = json.load(open(sys.argv[3]))
    before = parse(sys.argv[4]) if len(sys.argv) > 4 else None
    gone = [k for k in changed if changed[k] is None]
    for k in gone:
        del changed[k]
    dropped = [k for k in gone if k in status and (before is None or status[k] == before.get(k))]
    for k in dropped:
        del status[k]
    if dropped:
        print("  removed below, dropped here:", " ".join(sorted(k.split("|")[0] for k in dropped)))
    kept = [k for k in gone if k in status and k not in dropped]
    if kept:
        print("  removed below, kept (changed by this layer):", " ".join(sorted(k.split("|")[0] for k in kept)))
    if before is not None:
        installed = lambda st, k: k in st and field(st[k], "Status") == "install ok installed"
        removed = [k for k in changed if installed(before, k) and not installed(status, k)]
        for k in removed:
            del changed[k]
        if removed:
            print("  kept removed by this layer:", " ".join(sorted(k.split("|")[0] for k in removed)))
    status.update(changed)
    write(sys.argv[2], status)
