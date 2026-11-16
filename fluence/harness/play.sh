#!/bin/bash
# play.sh -- plays the ab.sh clips in order (A, B, C)
cd /tmp/sb4fr
for f in A-*.wav B-*.wav C-*.wav; do [ -f "$f" ] || continue; printf '\n\033[1mPlaying %s\033[0m\n' "${f%.wav}"
  if [ "$(id -u)" = 0 ]; then sudo -u ubuntu XDG_RUNTIME_DIR=/run/user/1000 pw-play "$f"; else pw-play "$f"; fi; sleep 1; done
