#!/bin/bash
# Renders the sb4edge rEFInd theme (runs in sb4build: rsvg-convert, Ubuntu Sans font). Output: refind/theme/sb4edge/
set -e
cd "$(dirname "$0")"
command -v rsvg-convert >/dev/null || { apt-get update -qq >/dev/null; apt-get install -y -qq librsvg2-bin fonts-ubuntu python3-pil >/dev/null; }
rm -rf svg sb4edge; python3 make-theme.py svg
mkdir -p sb4edge
for f in svg/*.svg; do rsvg-convert "$f" -o "sb4edge/$(basename "${f%.svg}").png"; done
cp theme.conf sb4edge/theme.conf
du -sh sb4edge; ls -l sb4edge
