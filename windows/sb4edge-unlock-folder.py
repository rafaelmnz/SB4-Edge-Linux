# sb4edge: "Unlock folder" / "Lock folder" in GNOME Files' right-click menu for folders on the Windows drive.
# The drive is mounted read-only (sb4edge-windows-mount); unlocking makes the folder and everything under it
# writable after a password prompt (pkexec), and it stays unlocked across reboots until "Lock folder".
# The menu follows the saved list of unlocked folders (/var/lib/sb4edge/windows-unlocked, kept by the helper),
# cross-checked with the live mounts, so an unlocked folder offers "Lock folder" and a locked one "Unlock folder";
# a folder inside an unlocked one offers to lock that parent.
import os

from gi.repository import GObject, Gio, GLib, Nautilus

HELPER = "/usr/lib/sb4edge/sb4edge-windows-mount"
LIST = "/var/lib/sb4edge/windows-unlocked"
RW = "/run/sb4edge/windows-rw"


def _unescape(s):
    return s.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\")


def _drive_root():
    """Mount point of the read-only Windows view: the bind of the hidden read-write mount ($RW) at its root."""
    try:
        lines = open("/proc/self/mountinfo").read().splitlines()
    except OSError:
        return None
    rw_src = None
    for line in lines:
        f = line.split()
        if _unescape(f[4]) == RW:
            rw_src = f[2]          # major:minor of the NTFS mount
    if not rw_src:
        return None
    for line in lines:
        f = line.split()
        if f[2] == rw_src and f[3] == "/" and _unescape(f[4]) != RW:
            return _unescape(f[4])
    return None


def _unlocked(root):
    """Folders (relative to the volume root) that are unlocked: the saved list plus writable binds now mounted."""
    rels = set()
    try:
        rels.update(l.strip() for l in open(LIST) if l.strip())
    except OSError:
        pass
    try:
        for line in open("/proc/self/mountinfo"):
            f = line.split()
            target = _unescape(f[4])
            if target.startswith(root + "/") and "rw" in f[5].split(","):
                rels.add(os.path.relpath(target, root))
    except OSError:
        pass
    return rels


class UnlockFolderMenu(GObject.GObject, Nautilus.MenuProvider):
    def _run(self, action, path):
        def done(proc, res, _data=None):
            try:
                _ok, _out, err = proc.communicate_utf8_finish(res)
            except GLib.Error:
                return
            if proc.get_exit_status() not in (0, 126, 127):   # 126/127: password prompt cancelled
                msg = (err or "").strip().splitlines()[-1:] or ["failed"]
                Gio.Subprocess.new(["notify-send", "-i", "dialog-error", "Windows drive", msg[0]], 0)
        proc = Gio.Subprocess.new(["pkexec", HELPER, action, path],
                                  Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
        proc.communicate_utf8_async(None, None, done, None)

    def _item(self, name, label, tip, action, path):
        item = Nautilus.MenuItem(name=name, label=label, tip=tip)
        item.connect("activate", lambda *_: self._run(action, path))
        return item

    def get_file_items(self, files):
        if len(files) != 1 or not files[0].is_directory():
            return []
        loc = files[0].get_location()
        path = loc.get_path() if loc else None
        root = _drive_root()
        if not path or not root or not (path == root or path.startswith(root + "/")):
            return []
        rel = os.path.relpath(path, root)
        unlocked = _unlocked(root)
        if rel in unlocked:
            return [self._item("Sb4edge::LockFolder", "Lock folder", "Make this folder read-only again",
                               "lock-folder", path)]
        parents = [u for u in unlocked if u == "." or rel.startswith(u + "/")]
        if parents:
            parent = max(parents, key=len)
            name = os.path.basename(root) if parent == "." else os.path.basename(parent)
            return [self._item("Sb4edge::LockFolder", f"Lock parent folder “{name}”",
                               f"This folder is writable because “{name}” is unlocked; make that read-only again",
                               "lock-folder", os.path.join(root, parent) if parent != "." else root)]
        return [self._item("Sb4edge::UnlockFolder", "Unlock folder",
                           "Make this folder and its subfolders writable (asks for your password)",
                           "unlock-folder", path)]
