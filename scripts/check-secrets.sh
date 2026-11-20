#!/bin/sh
# Run before every push: lists files that would be published and contain personal data. Pass extra words to look
# for (e.g. a username) as arguments; they are never stored in the repository and match in any case.
# Known, expected matches are listed in scripts/check-secrets.allow (file, a tab, then the exact line); only those
# exact lines are skipped, so a new match in the same file is still reported.
# Exit 1 if anything is found.
cd "$(dirname "$0")/.." || exit 2
P='192\.168\.[0-9]+\.[0-9]+|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|PRIVATE KEY|tskey-|@gmail\.com|/Users/[a-z]|/home/[a-z]+'
W=
for w in "$@"; do W="${W:+$W|}$w"; done
ALLOW=scripts/check-secrets.allow
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	files=$(git ls-files --cached --others --exclude-standard)
else
	# No repository yet: skip the directories .gitignore excludes.
	prune=$(sed -n 's|^\([A-Za-z0-9_./-]*\)/$|-path ./\1 -prune -o|p' .gitignore | tr '\n' ' ')
	files=$(eval "find . $prune -type f ! -name '*.deb' ! -name '*.ko' ! -name '*.iso' ! -name '*.log' ! -name HANDOFF.md -print" | sed 's|^\./||')
fi
found=0
for f in $files; do
	case $f in scripts/check-secrets.sh|"$ALLOW") continue ;; esac
	hits=$( { grep -nIE "$P" "$f" 2>/dev/null; [ -z "$W" ] || grep -nIEi "$W" "$f" 2>/dev/null; } | sort -t: -k1,1n -u |
		while IFS= read -r l; do
			text=${l#*:}
			[ -f "$ALLOW" ] && grep -qxF "$(printf '%s\t%s' "$f" "$text")" "$ALLOW" && continue
			printf '%s\n' "$l"
		done)
	[ -n "$hits" ] || continue
	echo "== $f"; printf '%s\n' "$hits" | cut -c1-160 | head -5; found=1
done
[ $found = 0 ] && echo "clean"
exit $found
