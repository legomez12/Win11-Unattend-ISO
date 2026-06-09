#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

die() {
  echo "$1"
  exit "${2:-1}"
}

count() {
  awk 'END { print NR + 0 }' "$1"
}

build_manifest() {
  local src_dir="$1" out_file="$2"
  : > "$out_file"
  while IFS= read -r -d '' file_path; do
    printf '%s|%s|%s\n' \
      "${file_path#"$src_dir"/}" \
      "$(stat -c '%s' "$file_path")" \
      "$(sha256sum "$file_path" | awk '{print $1}')" >> "$out_file"
  done < <(find "$src_dir" -type f -print0)
  sort -o "$out_file" "$out_file"
}

show_section() {
  local title="$1" file="$2"
  [ -s "$file" ] || return 0
  echo "$title"
  cat "$file"
  echo
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || die 'Usage: compare-isos.sh <iso_a> <iso_b> [report_file]'

ISO_A="$1"
ISO_B="$2"
REPORT_FILE="${3:-iso-compare-report.txt}"

for cmd in 7z sha256sum find sort stat awk comm mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd" 2
done

[ -f "$ISO_A" ] || die "ISO not found: $ISO_A" 3
[ -f "$ISO_B" ] || die "ISO not found: $ISO_B" 3

WORK_DIR="$(mktemp -d)"
DIR_A="$WORK_DIR/a"
DIR_B="$WORK_DIR/b"
MANIFEST_A="$WORK_DIR/manifest-a.txt"
MANIFEST_B="$WORK_DIR/manifest-b.txt"
PATHS_A="$WORK_DIR/paths-a.txt"
PATHS_B="$WORK_DIR/paths-b.txt"
ONLY_A="$WORK_DIR/only-a.txt"
ONLY_B="$WORK_DIR/only-b.txt"
CHANGED="$WORK_DIR/changed.txt"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$DIR_A" "$DIR_B"

echo 'Extracting ISO A...'
7z x "$ISO_A" -o"$DIR_A" >/dev/null

echo 'Extracting ISO B...'
7z x "$ISO_B" -o"$DIR_B" >/dev/null

echo 'Building manifests...'
build_manifest "$DIR_A" "$MANIFEST_A"
build_manifest "$DIR_B" "$MANIFEST_B"

cut -d '|' -f 1 "$MANIFEST_A" | sort > "$PATHS_A"
cut -d '|' -f 1 "$MANIFEST_B" | sort > "$PATHS_B"

comm -23 "$PATHS_A" "$PATHS_B" > "$ONLY_A"
comm -13 "$PATHS_A" "$PATHS_B" > "$ONLY_B"

awk -F '|' '
  NR == FNR {
    a[$1] = $2 "|" $3
    next
  }
  ($1 in a) && (a[$1] != $2 "|" $3) {
    print $1 "|A:" a[$1] "|B:" $2 "|" $3
  }
' "$MANIFEST_A" "$MANIFEST_B" > "$CHANGED"

count_total_a="$(count "$MANIFEST_A")"
count_total_b="$(count "$MANIFEST_B")"
count_only_a="$(count "$ONLY_A")"
count_only_b="$(count "$ONLY_B")"
count_changed="$(count "$CHANGED")"

{
  echo "ISO A: $ISO_A"
  echo "ISO B: $ISO_B"
  echo
  echo "Total files in ISO A: $count_total_a"
  echo "Total files in ISO B: $count_total_b"
  echo "Only in ISO A: $count_only_a"
  echo "Only in ISO B: $count_only_b"
  echo "Same path but different content: $count_changed"
  echo

  show_section '--- Files only in ISO A ---' "$ONLY_A"
  show_section '--- Files only in ISO B ---' "$ONLY_B"
  show_section '--- Files with same path but different size/hash ---' "$CHANGED"

  [ "$count_only_a" -eq 0 ] && [ "$count_only_b" -eq 0 ] && [ "$count_changed" -eq 0 ] &&
    echo 'No file-level differences detected.'
} | tee "$REPORT_FILE"

echo "Comparison report written to: $REPORT_FILE"
