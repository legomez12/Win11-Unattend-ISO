#!/usr/bin/env bash
set -euo pipefail

# Mirrors this WSL workspace to a Windows folder (mounted at /mnt/c/...)
# Usage:
#   bash sync-to-windows.sh                 # sync to default /mnt/c/MV-ISO
#   bash sync-to-windows.sh /mnt/c/MV-ISO   # sync to custom destination
#   bash sync-to-windows.sh --dry-run       # preview changes only

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST_DIR="/mnt/c/MV-ISO"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    *)
      DST_DIR="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$DST_DIR" ]]; then
  echo "Destination does not exist: $DST_DIR" >&2
  exit 1
fi

RSYNC_ARGS=(
  -avh
  --delete
  --exclude=.git/
  --exclude=.vscode/
  --exclude=.idea/
  --exclude=*.iso
  --exclude=autounattend.xml
  --exclude=*.tmp
  --exclude=*.log
)

if [[ $DRY_RUN -eq 1 ]]; then
  RSYNC_ARGS+=(--dry-run)
  echo "[DRY RUN] Previewing sync: $SRC_DIR/ -> $DST_DIR/"
else
  echo "Syncing: $SRC_DIR/ -> $DST_DIR/"
fi

rsync "${RSYNC_ARGS[@]}" "$SRC_DIR/" "$DST_DIR/"

echo "Done."
