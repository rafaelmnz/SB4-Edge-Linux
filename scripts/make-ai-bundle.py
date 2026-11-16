#!/usr/bin/env python3
"""Build sb4edge-ai-bundle.md: one Markdown file with everything a person or an AI needs to review or redo this
project - the audit guide, agent guide, knowledge base, notes, and every text source under '### FILE:' headers,
then a manifest with the SHA-256 of every tracked file (included, omitted and binary).

  scripts/make-ai-bundle.py [output]      default: out/sb4edge-ai-bundle.md

Only files tracked by git are used, so the bundle matches the commit named in its header (commit first).
"""
import hashlib, os, re, subprocess, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
OUT = sys.argv[1] if len(sys.argv) > 1 else 'out/sb4edge-ai-bundle.md'
MAX = 64 * 1024   # larger text files are listed in the manifest only

# Read in this order first; everything else follows in path order.
FRONT = ['ai/AUDIT.md', 'AGENTS.md', 'ai/KNOWLEDGE.md', 'README.md', 'INSTALL.md',
         'docs/DEVELOPMENT-NOTES.md', 'docs/HARDWARE-FINDINGS.md']
# Not inlined: third-party data, generated files, design drafts. Still hashed in the manifest.
OMIT = [
    (r'^fw/', 'third-party firmware (Windows driver package)'),
    (r'^windows-files/|^windows/', 'third-party files from Windows'),
    (r'^sensors/qcom-root/|^sensors/windows-persist/', 'third-party sensor configuration (Windows driver package)'),
    (r'^fluence/tplg/.*\.conf$', 'generated topology source (see fluence/NOTES.md)'),
    (r'^fluence/(cal|cal-chain|caldump|gkvdump|ko)(/|$)', 'calibration data / binaries'),
    (r'^fluence/acdb-graphs\.txt$', 'generated dump of the Windows ACDB'),
    (r'^refind/mockup/', 'boot menu design drafts'),
    (r'^ubuntu-config-', "Ubuntu's kernel config (input, unmodified)"),
    (r'(^|/)LICENSE$', 'license text'),
]
LANG = {'.sh': 'bash', '.py': 'python', '.c': 'c', '.h': 'c', '.patch': 'diff', '.diff': 'diff', '.dts': 'dts',
        '.dtsi': 'dts', '.json': 'json', '.yaml': 'yaml', '.yml': 'yaml', '.md': 'markdown', '.service': 'ini',
        '.conf': 'ini', '.rules': 'udev', '.m4': 'm4', '.cfg': 'text', '.html': 'html', '.js': 'javascript'}


def git(*a):
    return subprocess.run(['git', *a], check=True, capture_output=True, text=True).stdout.strip()


def is_text(data):
    if b'\0' in data:
        return False
    try:
        data.decode('utf-8')
        return True
    except UnicodeDecodeError:
        return False


def fence(text):
    longest = max((len(m) for m in re.findall(r'`{3,}', text)), default=0)
    return '`' * max(3, longest + 1)


files = git('ls-files').splitlines()
entries = []   # (path, size, sha256, status)
bodies = {}
for f in files:
    if not os.path.isfile(f):
        continue
    data = open(f, 'rb').read()
    sha = hashlib.sha256(data).hexdigest()
    reason = next((r for p, r in OMIT if re.search(p, f)), None)
    if reason is None and not is_text(data):
        reason = 'binary'
    if reason is None and len(data) > MAX and f not in FRONT:
        reason = f'text larger than {MAX // 1024} KiB'
    if reason is None:
        bodies[f] = data.decode('utf-8')
    entries.append((f, len(data), sha, reason or 'included'))

order = [f for f in FRONT if f in bodies] + sorted(f for f in bodies if f not in FRONT)
commit = git('rev-parse', 'HEAD')
dirty = bool(git('status', '--porcelain', '--untracked-files=no'))
date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC')

out = []
w = out.append
w('# SB4-Edge-Linux: AI review bundle\n')
w('Linux for the Samsung Galaxy Book4 Edge 16" (Snapdragon X Elite X1E-84-100): knowledge base, development notes '
  'and every text source of https://github.com/rafaelmnz/SB4-Edge-Linux in one file, for review by people and AI '
  'models, or as a starting point to redo the work another way.\n')
w(f'- Commit: `{commit}`{" (with uncommitted changes)" if dirty else ""}')
w(f'- Generated: {date} by `scripts/make-ai-bundle.py`')
w(f'- Files: {len(order)} inlined, {len(entries) - len(order)} listed by hash only (see the manifest at the end)\n')
w('How to use: read the first file (`ai/AUDIT.md`) for what to review, `ai/KNOWLEDGE.md` for the hardware facts and '
  'solutions. Each file starts with a line `### FILE: <path>`; cite those paths in findings. Check this bundle '
  'against the repository with the SHA-256 values in the manifest.\n')
w('## Contents\n')
for f in order:
    w(f'- `{f}`')
w('')
for f in order:
    text = bodies[f]
    fe = fence(text)
    lang = LANG.get(os.path.splitext(f)[1], '')
    w(f'### FILE: {f}\n')
    w(f'{fe}{lang}')
    w(text.rstrip('\n'))
    w(f'{fe}\n')
w('## Manifest\n')
w('Every file tracked at the commit above: size in bytes, SHA-256, and whether it is inlined.\n')
w('| File | Bytes | SHA-256 | Status |')
w('|---|---:|---|---|')
for f, size, sha, status in entries:
    w(f'| `{f}` | {size} | `{sha}` | {status} |')
w('')

os.makedirs(os.path.dirname(OUT) or '.', exist_ok=True)
with open(OUT, 'w') as fh:
    fh.write('\n'.join(out))
print(f'{OUT}: {os.path.getsize(OUT)} bytes, {len(order)} files inlined, {len(entries) - len(order)} hashed only')
