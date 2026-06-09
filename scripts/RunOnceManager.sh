#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

component='RunOnceManager'
write_log "$component" START 'Generating first-logon one-time runner.'

STAGE_ROOT=''
BROWSER_ENTRIES_FILE=''
APPLICATION_ENTRIES_FILE=''
ADDITIONAL_ENTRIES_FILE=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage-root)
      STAGE_ROOT="$2"
      shift 2
      ;;
    --browser-entries-file)
      BROWSER_ENTRIES_FILE="$2"
      shift 2
      ;;
    --application-entries-file)
      APPLICATION_ENTRIES_FILE="$2"
      shift 2
      ;;
    --additional-entries-file)
      ADDITIONAL_ENTRIES_FILE="$2"
      shift 2
      ;;
    *)
      stop_fail_fast "Unknown argument: $1"
      ;;
  esac
done

if [ -z "$STAGE_ROOT" ]; then
  stop_fail_fast 'Missing required argument --stage-root'
fi

entry_lines=()
for entries_file in "$BROWSER_ENTRIES_FILE" "$APPLICATION_ENTRIES_FILE" "$ADDITIONAL_ENTRIES_FILE"; do
  if [ -n "$entries_file" ] && [ -f "$entries_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && entry_lines+=("$line")
    done < "$entries_file"
  fi
done

if [ "${#entry_lines[@]}" -eq 0 ]; then
  write_log "$component" INFO 'No entries provided. Skipping RunOnce script generation.'
  write_log "$component" CLEANUP 'RunOnce manager cleanup complete.'
  exit 0
fi

startup_dir="$STAGE_ROOT/sources/\$OEM\$/\$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
new_directory_if_missing "$startup_dir"
startup_script_path="$startup_dir/install-apps-once.cmd"

lines=(
  '@echo off'
  'setlocal'
  'echo Running first-login installers...'
  ''
)

for entry_line in "${entry_lines[@]}"; do
  entry_name="${entry_line%%$'\t'*}"
  entry_command="${entry_line#*$'\t'}"

  if [ -z "$entry_name" ] || [ -z "$entry_command" ] || [ "$entry_name" = "$entry_line" ]; then
    stop_fail_fast 'RunOnce entry is missing Name or Command.'
  fi

  lines+=("echo $entry_name...")
  lines+=("$entry_command")
  lines+=('if errorlevel 1 (')
  lines+=('    echo Installer returned a non-zero exit code: %errorlevel%')
  lines+=(') else (')
  lines+=("    echo Completed: $entry_name")
  lines+=(')')
  lines+=('')
done

lines+=('if exist "C:\BrowserInstallers" rmdir /s /q "C:\BrowserInstallers" >nul 2>&1')
lines+=('if exist "C:\AppInstallers" rmdir /s /q "C:\AppInstallers" >nul 2>&1')
lines+=('echo Done.')
lines+=('del /f /q "%~f0" >nul 2>&1')
lines+=('endlocal')

write_crlf_file "$startup_script_path" "${lines[@]}"

write_log "$component" SUCCESS "Generated one-time startup runner: $startup_script_path"
write_log "$component" CLEANUP 'RunOnce manager cleanup complete.'
