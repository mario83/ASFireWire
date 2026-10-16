#!/usr/bin/env bash
# Copy Prism Sound Orpheus.app bitmaps into a gitignored local folder.
# They are Prism Sound copyright; do not commit or ship them until a license
# is granted. The classic panel falls back to drawn controls if they are absent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/ASFW/Resources/OrpheusVendor"
INSTALLED_SRC="/Applications/Prism Sound/Orpheus.app/Contents/Resources"
SRC="${1:-}"

if [[ -z "$SRC" ]]; then
  if [[ -d "$INSTALLED_SRC" ]]; then
    SRC="$INSTALLED_SRC"
  else
    echo "usage: $0 [path/to/Orpheus.app/Contents/Resources]" >&2
    exit 1
  fi
fi

mkdir -p "$DEST"
SUPPORT="${HOME}/Library/Application Support/ASFW/OrpheusVendor"
mkdir -p "$SUPPORT"
copied=0
for path in "$SRC"/*.{bmp,gif,png,icns}; do
  [[ -e "$path" ]] || continue
  name="$(basename "$path")"
  cp -f "$path" "$DEST/$name"
  cp -f "$path" "$SUPPORT/$name"
  copied=$((copied + 1))
done

cat > "$DEST/ORIGIN.txt" <<EOF
Prism Sound Orpheus.app artwork.
Local copy only — not licensed for redistribution until Prism Sound grants a release.
Source: $SRC
Imported: $(date)
Files: $copied
EOF

echo "Imported $copied files into $DEST"
echo "Also copied to $SUPPORT for the installed Debug app."
echo "These files are gitignored. Do not add them to a commit."
