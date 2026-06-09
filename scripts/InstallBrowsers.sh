#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

component='InstallBrowsers'
write_log "$component" START 'Preparing browser installer staging.'

BROWSER_CONFIG_PATH=''
STAGE_ROOT=''
BROWSERS=''
ENTRIES_FILE=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --browser-config-path)
      BROWSER_CONFIG_PATH="$2"
      shift 2
      ;;
    --stage-root)
      STAGE_ROOT="$2"
      shift 2
      ;;
    --browsers)
      BROWSERS="$2"
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

if [ -z "$STAGE_ROOT" ]; then
  stop_fail_fast 'Missing required argument --stage-root'
fi

if [ -n "$ENTRIES_FILE" ]; then
  : > "$ENTRIES_FILE"
fi

if [ -z "$BROWSERS" ]; then
  write_log "$component" INFO 'No browsers selected. Skipping browser staging.'
  write_log "$component" CLEANUP 'Browser staging cleanup complete.'
  exit 0
fi

if [ -z "$BROWSER_CONFIG_PATH" ]; then
  stop_fail_fast 'Missing required argument --browser-config-path'
fi

if [ ! -f "$BROWSER_CONFIG_PATH" ]; then
  stop_fail_fast "Browser configuration file not found: $BROWSER_CONFIG_PATH"
fi

if is_command_available jq; then
  mapfile -t all_browser_names < <(jq -r '.browsers[].name' "$BROWSER_CONFIG_PATH" | sort)
elif is_command_available python3; then
  mapfile -t all_browser_names < <(python3 - "$BROWSER_CONFIG_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

names = []
for item in data.get('browsers', []):
    name = item.get('name')
    if isinstance(name, str) and name:
        names.append(name)

for name in sorted(names):
    print(name)
PY
)
else
  stop_fail_fast 'Install jq or python3 to parse browser configuration JSON.'
fi

if [ "${#all_browser_names[@]}" -eq 0 ]; then
  stop_fail_fast "Browser configuration is invalid: $BROWSER_CONFIG_PATH"
fi

declare -A valid_browser_map=()
for name in "${all_browser_names[@]}"; do
  valid_browser_map["$name"]=1
done

selected=()
IFS=',' read -ra raw_browsers <<< "$BROWSERS"
for raw in "${raw_browsers[@]}"; do
  browser="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
  [ -n "$browser" ] || continue

  if [ "$browser" = 'all' ]; then
    selected=("${all_browser_names[@]}")
    break
  fi

  if [ -z "${valid_browser_map[$browser]:-}" ]; then
    stop_fail_fast "Browser '$browser' is not defined in configuration file: $BROWSER_CONFIG_PATH"
  fi

  duplicate=0
  for existing in "${selected[@]:-}"; do
    if [ "$existing" = "$browser" ]; then
      duplicate=1
      break
    fi
  done

  if [ "$duplicate" -eq 0 ]; then
    selected+=("$browser")
  fi
done

if [ "${#selected[@]}" -eq 0 ]; then
  write_log "$component" INFO 'No browsers selected. Skipping browser staging.'
  write_log "$component" CLEANUP 'Browser staging cleanup complete.'
  exit 0
fi

browser_stage_dir="$STAGE_ROOT/sources/\$OEM\$/\$1/BrowserInstallers"
new_directory_if_missing "$browser_stage_dir"

link_lines=()
for browser in "${selected[@]}"; do
  if is_command_available jq; then
    url="$(jq -r --arg n "$browser" '.browsers[] | select(.name == $n) | .url' "$BROWSER_CONFIG_PATH")"
    installer_file="$(jq -r --arg n "$browser" '.browsers[] | select(.name == $n) | .installerFile' "$BROWSER_CONFIG_PATH")"
    silent_args="$(jq -r --arg n "$browser" '.browsers[] | select(.name == $n) | .silentArgs' "$BROWSER_CONFIG_PATH")"
    display_name="$(jq -r --arg n "$browser" '.browsers[] | select(.name == $n) | .displayName' "$BROWSER_CONFIG_PATH")"
  else
    mapfile -t browser_values < <(python3 - "$BROWSER_CONFIG_PATH" "$browser" <<'PY'
import json
import sys

path = sys.argv[1]
name = sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)

selected = None
for item in data.get('browsers', []):
    if item.get('name') == name:
        selected = item
        break

if selected is None:
    print('')
    print('')
    print('')
    print('')
else:
    print(str(selected.get('url') or ''))
    print(str(selected.get('installerFile') or ''))
    print(str(selected.get('silentArgs') or ''))
    print(str(selected.get('displayName') or ''))
PY
)

    url="${browser_values[0]:-}"
    installer_file="${browser_values[1]:-}"
    silent_args="${browser_values[2]:-}"
    display_name="${browser_values[3]:-}"
  fi

  if [ -z "$url" ] || [ -z "$installer_file" ] || [ -z "$silent_args" ] || [ -z "$display_name" ] || [ "$url" = 'null' ]; then
    stop_fail_fast "Browser configuration entry is missing required fields in: $BROWSER_CONFIG_PATH"
  fi

  output_path="$browser_stage_dir/$installer_file"
  write_log "$component" INFO "Downloading $browser installer."
  curl -fL -o "$output_path" "$url"

  [ -f "$output_path" ] || stop_fail_fast "Failed to download installer for $browser"
  [ -s "$output_path" ] || stop_fail_fast "Downloaded installer for $browser is empty"

  link_lines+=("$browser = $url")

  if [ -n "$ENTRIES_FILE" ]; then
    printf 'Install %s\tC:\\BrowserInstallers\\%s %s\n' "$display_name" "$installer_file" "$silent_args" >> "$ENTRIES_FILE"
  fi
done

links_file="$browser_stage_dir/download-links.txt"
write_crlf_file "$links_file" "${link_lines[@]}"

write_log "$component" SUCCESS "Staged browser installers in $browser_stage_dir"
write_log "$component" CLEANUP 'Browser staging cleanup complete.'
