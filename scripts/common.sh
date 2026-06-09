#!/usr/bin/env bash
set -euo pipefail

write_log() {
  local component="$1"
  local status="$2"
  local message="$3"
  echo "[$component][$status] $message"
}

stop_fail_fast() {
  local message="$1"
  echo "$message" >&2
  exit 1
}

write_crlf_file() {
  local target="$1"
  shift

  : > "$target"
  for line in "$@"; do
    printf '%s\r\n' "$line" >> "$target"
  done
}

new_directory_if_missing() {
  local path="$1"
  if [ ! -d "$path" ]; then
    mkdir -p "$path"
  fi
}

split_csv_to_lines() {
  local value="$1"
  local token
  IFS=',' read -ra parts <<< "$value"
  for token in "${parts[@]}"; do
    token="$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "$token" ]; then
      echo "$token"
    fi
  done
}

is_command_available() {
  command -v "$1" >/dev/null 2>&1
}
