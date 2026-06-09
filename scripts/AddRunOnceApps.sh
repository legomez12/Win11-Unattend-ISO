#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

component='AddRunOnceApps'
write_log "$component" START 'Preparing local app installer staging.'

STAGE_ROOT=''
APP_FOLDERS=''
DEFAULT_APPS_FOLDER=''
ENTRIES_FILE=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage-root)
      STAGE_ROOT="$2"
      shift 2
      ;;
    --app-folders)
      APP_FOLDERS="$2"
      shift 2
      ;;
    --default-apps-folder)
      DEFAULT_APPS_FOLDER="$2"
      shift 2
      ;;
    --entries-file)
      ENTRIES_FILE="$2"
      shift 2
      ;;
    *)
      stop_fail_fast "Unknown argument: $1"
      ;;
  esac
done

if [ -z "$STAGE_ROOT" ] || [ -z "$DEFAULT_APPS_FOLDER" ]; then
  stop_fail_fast 'Missing required arguments --stage-root and/or --default-apps-folder'
fi

if [ -n "$ENTRIES_FILE" ]; then
  : > "$ENTRIES_FILE"
fi

using_default=0
if [ -z "$APP_FOLDERS" ]; then
  using_default=1
  folder_list=("$DEFAULT_APPS_FOLDER")
else
  IFS=',' read -ra raw_folder_list <<< "$APP_FOLDERS"
  folder_list=()
  for folder in "${raw_folder_list[@]}"; do
    trimmed="$(echo "$folder" | xargs)"
    [ -n "$trimmed" ] && folder_list+=("$trimmed")
  done
fi

if [ "${#folder_list[@]}" -eq 0 ]; then
  stop_fail_fast 'No app folder paths were provided after parsing AppFolders.'
fi

app_stage_dir="$STAGE_ROOT/sources/\$OEM\$/\$1/AppInstallers"
new_directory_if_missing "$app_stage_dir"

staged_count=0
for folder in "${folder_list[@]}"; do
  if [ ! -d "$folder" ]; then
    if [ "$using_default" -eq 1 ]; then
      write_log "$component" INFO 'Default ./apps folder missing. Skipping local app staging.'
      write_log "$component" CLEANUP 'Application staging cleanup complete.'
      exit 0
    fi
    stop_fail_fast "User-specified app folder not found: $folder"
  fi

  mapfile -d '' -t installers < <(find "$folder" -type f \( -iname '*.exe' -o -iname '*.msi' \) -print0 | sort -z)
  if [ "${#installers[@]}" -eq 0 ]; then
    if [ "$using_default" -eq 1 ]; then
      write_log "$component" INFO 'Default ./apps folder is empty. Skipping local app staging.'
      write_log "$component" CLEANUP 'Application staging cleanup complete.'
      exit 0
    fi
    stop_fail_fast "User-specified app folder has no .exe/.msi installers: $folder"
  fi

  root_name="$(basename "$folder")"
  for installer in "${installers[@]}"; do
    relative="${installer#"$folder"/}"
    if [ "$using_default" -eq 0 ] && [ "${#folder_list[@]}" -gt 1 ]; then
      relative="$root_name/$relative"
    fi

    destination="$app_stage_dir/$relative"
    new_directory_if_missing "$(dirname "$destination")"
    cp "$installer" "$destination"

    win_relative="${relative//\//\\}"
    filename="$(basename "$installer")"

    if [[ "${installer,,}" == *.msi ]]; then
      command="msiexec /i \"C:\\AppInstallers\\$win_relative\" /qn /norestart"
      entry_name="Install MSI $filename"
    else
      command="\"C:\\AppInstallers\\$win_relative\""
      entry_name="Install EXE $filename"
    fi

    if [ -n "$ENTRIES_FILE" ]; then
      printf '%s\t%s\n' "$entry_name" "$command" >> "$ENTRIES_FILE"
    fi

    staged_count=$((staged_count + 1))
  done
done

write_log "$component" SUCCESS "Staged $staged_count application installers in $app_stage_dir"
write_log "$component" CLEANUP 'Application staging cleanup complete.'
