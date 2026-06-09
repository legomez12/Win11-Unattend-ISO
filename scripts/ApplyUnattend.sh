#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

component='ApplyUnattend'

INPUT_ISO=''
OUTPUT_ISO=''
UNATTEND_XML_PATH=''
WORKING_DIRECTORY=''
OEM_STAGE_ROOT=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input-iso)
      INPUT_ISO="$2"
      shift 2
      ;;
    --output-iso)
      OUTPUT_ISO="$2"
      shift 2
      ;;
    --unattend-xml-path)
      UNATTEND_XML_PATH="$2"
      shift 2
      ;;
    --working-directory)
      WORKING_DIRECTORY="$2"
      shift 2
      ;;
    --oem-stage-root)
      OEM_STAGE_ROOT="$2"
      shift 2
      ;;
    *)
      stop_fail_fast "Unknown argument: $1"
      ;;
  esac
done

extract_dir="$WORKING_DIRECTORY/iso-extract"

write_log "$component" START 'Starting unattended ISO processing.'

cleanup() {
  write_log "$component" CLEANUP 'Cleaning temporary extraction directory.'
  rm -rf "$extract_dir"
}
trap cleanup EXIT

[ -f "$INPUT_ISO" ] || stop_fail_fast "Input ISO not found: $INPUT_ISO"
[ -f "$UNATTEND_XML_PATH" ] || stop_fail_fast "Unattend XML not found: $UNATTEND_XML_PATH"
[ -s "$UNATTEND_XML_PATH" ] || stop_fail_fast "Unattend XML is empty: $UNATTEND_XML_PATH"

is_command_available 7z || stop_fail_fast '7z not found. Install p7zip-full.'
is_command_available xorriso || stop_fail_fast 'xorriso not found.'

rm -rf "$extract_dir"
mkdir -p "$extract_dir"

write_log "$component" INFO 'Extracting ISO with 7-Zip.'
7z x "$INPUT_ISO" -o"$extract_dir" >/dev/null

cp "$UNATTEND_XML_PATH" "$extract_dir/autounattend.xml"
write_log "$component" INFO 'Injected autounattend.xml into extracted ISO root.'

if [ -n "$OEM_STAGE_ROOT" ] && [ -d "$OEM_STAGE_ROOT" ]; then
  shopt -s dotglob
  stage_items=("$OEM_STAGE_ROOT"/*)
  shopt -u dotglob
  if [ "${#stage_items[@]}" -gt 0 ] && [ -e "${stage_items[0]}" ]; then
    write_log "$component" INFO "Merging staged OEM content from $OEM_STAGE_ROOT"
    cp -a "$OEM_STAGE_ROOT"/. "$extract_dir"/
  fi
fi

[ -f "$extract_dir/boot/etfsboot.com" ] || stop_fail_fast 'Missing BIOS boot file: boot/etfsboot.com'
[ -f "$extract_dir/efi/microsoft/boot/efisys.bin" ] || stop_fail_fast 'Missing UEFI boot file: efi/microsoft/boot/efisys.bin'

write_log "$component" INFO 'Building custom ISO with xorriso.'
xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid 'WIN11_CUSTOM' \
  -eltorito-boot boot/etfsboot.com \
  -no-emul-boot \
  -boot-load-size 8 \
  -eltorito-catalog boot/boot.cat \
  -eltorito-alt-boot \
  -e efi/microsoft/boot/efisys.bin \
  -no-emul-boot \
  -output "$OUTPUT_ISO" \
  "$extract_dir" >/dev/null

write_log "$component" SUCCESS "Created output ISO: $OUTPUT_ISO"
