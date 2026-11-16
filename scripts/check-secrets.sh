#!/bin/sh
# Run before every push: lists files that would be published and contain personal data. Pass extra words to look
# for (e.g. a username) as arguments; they are never stored in the repository.
# Exit 1 if anything is found.
cd "$(dirname "$0")/.." || exit 2
P='192\.168\.[0-9]+\.[0-9]+|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|PRIVATE KEY|tskey-|@gmail\.com|/Users/[a-z]|/home/[a-z]+'
for w in "$@"; do P="$P|$w"; done
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	files=$(git ls-files --cached --others --exclude-standard)
else
	# No repository yet: skip the directories .gitignore excludes.
	prune=$(sed -n 's|^\([A-Za-z0-9_./-]*\)/$|-path ./\1 -prune -o|p' .gitignore | tr '\n' ' ')
	files=$(eval "find . $prune -type f ! -name '*.deb' ! -name '*.ko' ! -name '*.iso' ! -name '*.log' ! -name HANDOFF.md -print" | sed 's|^\./||')
fi
found=0
for f in $files; do
	[ "$f" = scripts/check-secrets.sh ] && continue
	grep -IqE -i "$P" "$f" 2>/dev/null || continue
	echo "== $f"; grep -nIE -i "$P" "$f" | cut -c1-160 | head -5; found=1
done
[ $found = 0 ] && echo "clean"
exit $found
