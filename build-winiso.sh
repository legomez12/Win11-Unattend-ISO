#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: build-winiso.sh <input_iso> <output_iso> [-Browsers <chrome|opera|firefox|brave|all>[,<browser>...]] [-AppFolders <folder1,folder2,...>] [-SettingsConfigPath <path>] [-BrowserConfigPath <path>] [-UnattendUri <uri>] [-UnattendXmlPath <path>]'
  exit 1
}

if [ "$#" -lt 2 ]; then
  usage
fi

INPUT_ISO="$1"
OUTPUT_ISO="$2"
shift 2

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_ROOT/scripts/common.sh"

APP_FOLDERS=''
SETTINGS_CONFIG_PATH=''
BROWSER_CONFIG_PATH=''
UNATTEND_URI=''
UNATTEND_XML_PATH=''
BROWSERS=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    -Browsers|-browsers)
      [ "$#" -ge 2 ] || stop_fail_fast '-Browsers requires a value'
      BROWSERS="$2"
      shift 2
      ;;
    -AppFolders|-appfolders)
      [ "$#" -ge 2 ] || stop_fail_fast '-AppFolders requires a value'
      APP_FOLDERS="$2"
      shift 2
      ;;
    -SettingsConfigPath|-settingsconfigpath)
      [ "$#" -ge 2 ] || stop_fail_fast '-SettingsConfigPath requires a value'
      SETTINGS_CONFIG_PATH="$2"
      shift 2
      ;;
    -BrowserConfigPath|-browserconfigpath)
      [ "$#" -ge 2 ] || stop_fail_fast '-BrowserConfigPath requires a value'
      BROWSER_CONFIG_PATH="$2"
      shift 2
      ;;
    -UnattendUri|-unattenduri)
      [ "$#" -ge 2 ] || stop_fail_fast '-UnattendUri requires a value'
      UNATTEND_URI="$2"
      shift 2
      ;;
    -UnattendXmlPath|-unattendxmlpath)
      [ "$#" -ge 2 ] || stop_fail_fast '-UnattendXmlPath requires a value'
      UNATTEND_XML_PATH="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$SETTINGS_CONFIG_PATH" ]; then
  SETTINGS_CONFIG_PATH="$SCRIPT_ROOT/config/orchestrator.sh.json"
fi

resolve_settings_path() {
  local path="$1"
  if [ -z "$path" ]; then
    echo ""
    return
  fi

  if [[ "$path" = /* ]]; then
    echo "$path"
  else
    echo "$SCRIPT_ROOT/$path"
  fi
}

[ -f "$SETTINGS_CONFIG_PATH" ] || stop_fail_fast "Settings config not found: $SETTINGS_CONFIG_PATH"
if is_command_available jq; then
  component="$(jq -r '.componentName' "$SETTINGS_CONFIG_PATH")"
  default_browser_config_path="$(jq -r '.browserConfigPath' "$SETTINGS_CONFIG_PATH")"
  default_unattend_uri="$(jq -r '.unattendUri' "$SETTINGS_CONFIG_PATH")"
  downloaded_unattend_file_name="$(jq -r '.downloadedUnattendFileName' "$SETTINGS_CONFIG_PATH")"
  working_root_name="$(jq -r '.workingRootName' "$SETTINGS_CONFIG_PATH")"
  stage_root_name="$(jq -r '.stageRootName' "$SETTINGS_CONFIG_PATH")"
  default_apps_folder_setting="$(jq -r '.defaultAppsFolder' "$SETTINGS_CONFIG_PATH")"
  install_browsers_script_setting="$(jq -r '.scripts.installBrowsers' "$SETTINGS_CONFIG_PATH")"
  add_runonce_apps_script_setting="$(jq -r '.scripts.addRunOnceApps' "$SETTINGS_CONFIG_PATH")"
  runonce_manager_script_setting="$(jq -r '.scripts.runOnceManager' "$SETTINGS_CONFIG_PATH")"
  apply_unattend_script_setting="$(jq -r '.scripts.applyUnattend' "$SETTINGS_CONFIG_PATH")"
elif is_command_available python3; then
  mapfile -t _settings < <(python3 - "$SETTINGS_CONFIG_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

scripts = data.get('scripts') or {}
values = [
    data.get('componentName', ''),
    data.get('browserConfigPath', ''),
    data.get('unattendUri', ''),
    data.get('downloadedUnattendFileName', ''),
    data.get('workingRootName', ''),
    data.get('stageRootName', ''),
    data.get('defaultAppsFolder', ''),
    scripts.get('installBrowsers', ''),
    scripts.get('addRunOnceApps', ''),
    scripts.get('runOnceManager', ''),
    scripts.get('applyUnattend', '')
]

for value in values:
    if value is None:
        value = ''
    print(str(value))
PY
)

  component="${_settings[0]:-}"
  default_browser_config_path="${_settings[1]:-}"
  default_unattend_uri="${_settings[2]:-}"
  downloaded_unattend_file_name="${_settings[3]:-}"
  working_root_name="${_settings[4]:-}"
  stage_root_name="${_settings[5]:-}"
  default_apps_folder_setting="${_settings[6]:-}"
  install_browsers_script_setting="${_settings[7]:-}"
  add_runonce_apps_script_setting="${_settings[8]:-}"
  runonce_manager_script_setting="${_settings[9]:-}"
  apply_unattend_script_setting="${_settings[10]:-}"
else
  stop_fail_fast 'Install jq or python3 to parse settings JSON.'
fi

for key_value in \
  "$component" \
  "$default_browser_config_path" \
  "$default_unattend_uri" \
  "$downloaded_unattend_file_name" \
  "$working_root_name" \
  "$stage_root_name" \
  "$default_apps_folder_setting" \
  "$install_browsers_script_setting" \
  "$add_runonce_apps_script_setting" \
  "$runonce_manager_script_setting" \
  "$apply_unattend_script_setting"; do
  [ -n "$key_value" ] && [ "$key_value" != 'null' ] || stop_fail_fast "Invalid or missing required setting in $SETTINGS_CONFIG_PATH"
done

resolved_browser_config_path="$BROWSER_CONFIG_PATH"
if [ -z "$resolved_browser_config_path" ]; then
  resolved_browser_config_path="$(resolve_settings_path "$default_browser_config_path")"
fi

resolved_unattend_uri="$UNATTEND_URI"
if [ -z "$resolved_unattend_uri" ]; then
  resolved_unattend_uri="$default_unattend_uri"
fi

install_browsers_script="$(resolve_settings_path "$install_browsers_script_setting")"
add_runonce_apps_script="$(resolve_settings_path "$add_runonce_apps_script_setting")"
runonce_manager_script="$(resolve_settings_path "$runonce_manager_script_setting")"
apply_unattend_script="$(resolve_settings_path "$apply_unattend_script_setting")"

working_root="${TMPDIR:-/tmp}/$working_root_name"
stage_root="$working_root/$stage_root_name"
default_apps_folder="$(resolve_settings_path "$default_apps_folder_setting")"

downloaded_unattend_path="$(pwd)/$downloaded_unattend_file_name"
cleanup_downloaded_unattend=0

write_log "$component" START 'Starting orchestration.'

cleanup_orchestrator() {
  write_log "$component" CLEANUP 'Running orchestrator cleanup.'
  if [ "$cleanup_downloaded_unattend" -eq 1 ] && [ -f "$downloaded_unattend_path" ]; then
    rm -f "$downloaded_unattend_path"
  fi
  rm -rf "$working_root"
}
trap cleanup_orchestrator EXIT

[ -f "$INPUT_ISO" ] || stop_fail_fast "Input ISO not found: $INPUT_ISO"

for child_script in "$install_browsers_script" "$add_runonce_apps_script" "$runonce_manager_script" "$apply_unattend_script"; do
  [ -f "$child_script" ] || stop_fail_fast "Required child script not found: $child_script"
done

if [ -f "$OUTPUT_ISO" ]; then
  write_log "$component" INFO "Removing existing output ISO: $OUTPUT_ISO"
  rm -f "$OUTPUT_ISO"
fi

if [ -d "$working_root" ]; then
  write_log "$component" INFO "Removing previous working directory: $working_root"
  rm -rf "$working_root"
fi

new_directory_if_missing "$stage_root"

resolved_unattend_path=''
if [ -n "$UNATTEND_XML_PATH" ]; then
  [ -f "$UNATTEND_XML_PATH" ] || stop_fail_fast "Provided UnattendXmlPath not found: $UNATTEND_XML_PATH"
  resolved_unattend_path="$UNATTEND_XML_PATH"
  write_log "$component" INFO "Using local unattended XML: $resolved_unattend_path"
else
  if [ -f "$downloaded_unattend_path" ]; then
    write_log "$component" INFO 'Existing autounattend.xml found, deleting to avoid confusion.'
    rm -f "$downloaded_unattend_path"
  fi

  write_log "$component" INFO 'Downloading autounattend.xml.'
  curl -fL -o "$downloaded_unattend_path" "$resolved_unattend_uri"

  [ -f "$downloaded_unattend_path" ] || stop_fail_fast 'autounattend.xml was not created by curl'
  [ -s "$downloaded_unattend_path" ] || stop_fail_fast 'autounattend.xml is empty'

  resolved_unattend_path="$downloaded_unattend_path"
  cleanup_downloaded_unattend=1
fi

browser_entries_file="$working_root/browser-entries.tsv"
app_entries_file="$working_root/app-entries.tsv"
new_directory_if_missing "$working_root"

bash "$install_browsers_script" \
  --browser-config-path "$resolved_browser_config_path" \
  --stage-root "$stage_root" \
  --browsers "$BROWSERS" \
  --entries-file "$browser_entries_file"

bash "$add_runonce_apps_script" \
  --stage-root "$stage_root" \
  --app-folders "$APP_FOLDERS" \
  --default-apps-folder "$default_apps_folder" \
  --entries-file "$app_entries_file"

if [ -s "$browser_entries_file" ] || [ -s "$app_entries_file" ]; then
  bash "$runonce_manager_script" \
    --stage-root "$stage_root" \
    --browser-entries-file "$browser_entries_file" \
    --application-entries-file "$app_entries_file"
else
  write_log "$component" INFO 'No browser or app entries generated. RunOnce startup script not required.'
fi

bash "$apply_unattend_script" \
  --input-iso "$INPUT_ISO" \
  --output-iso "$OUTPUT_ISO" \
  --unattend-xml-path "$resolved_unattend_path" \
  --working-directory "$working_root" \
  --oem-stage-root "$stage_root"

write_log "$component" SUCCESS "Done. Output ISO: $OUTPUT_ISO"