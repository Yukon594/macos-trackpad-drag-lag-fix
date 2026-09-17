#!/bin/zsh

# SPDX-License-Identifier: MIT
# Detect and restart current-user, third-party background Quartz Event Tap owners.

set -u

mode="${1:-restart}"

if [[ "$mode" == "--help" || "$mode" == "-h" ]]; then
  cat <<'EOF'
Usage:
  Double-click or run directly: discover and restart all detected third-party
  background input monitors

  --list: list candidates without restarting them
  --help: show this help
EOF
  exit 0
fi

if [[ "$mode" != "restart" && "$mode" != "--list" ]]; then
  echo "Unknown argument: $mode"
  exit 2
fi

ruby_runtime="/usr/bin/ruby"
if [[ ! -x "$ruby_runtime" ]]; then
  echo "The system is missing /usr/bin/ruby, so the Event Tap list cannot be read."
  exit 1
fi

task_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/input-tap-restart.XXXXXX") || exit 1
inspector_source="$task_temp_dir/event_tap_inspector.rb"
tap_output="$task_temp_dir/event-taps.tsv"

cleanup() {
  rm -f -- "$inspector_source" "$tap_output"
  rmdir "$task_temp_dir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

cat > "$inspector_source" <<'RUBY'
require 'fiddle/import'

module CoreGraphics
  extend Fiddle::Importer
  dlload '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'
  extern 'int CGGetEventTapList(unsigned int, void*, void*)'
end

count_buffer = [0].pack('L<')
count_pointer = Fiddle::Pointer[count_buffer]
exit(1) unless CoreGraphics.CGGetEventTapList(0, 0, count_pointer).zero?
count = count_pointer[0, 4].unpack1('L<')
exit(0) if count.zero?

record_size = 48
records = "\0" * (count * record_size)
records_pointer = Fiddle::Pointer[records]
filled_buffer = [count].pack('L<')
filled_pointer = Fiddle::Pointer[filled_buffer]
exit(1) unless CoreGraphics.CGGetEventTapList(count, records_pointer, filled_pointer).zero?
filled = filled_pointer[0, 4].unpack1('L<')

pids = {}
filled.times do |index|
  record = records_pointer[index * record_size, record_size]
  pid = record.byteslice(24, 4).unpack1('l<')
  pids[pid] = true
end

pids.keys.sort.each { |pid| puts pid }
RUBY

echo "Discovering third-party input monitors…"
if ! "$ruby_runtime" "$inspector_source" > "$tap_output"; then
  echo "Unable to read the Quartz Event Tap list."
  exit 1
fi

current_uid=$(id -u)
typeset -a candidate_pids candidate_names candidate_bundles
typeset -A seen_pids

is_background_app() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"
  local ui_element background_only

  [[ -f "$info_plist" ]] || return 1
  ui_element=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info_plist" 2>/dev/null || true)
  background_only=$(/usr/libexec/PlistBuddy -c 'Print :LSBackgroundOnly' "$info_plist" 2>/dev/null || true)
  [[ "$ui_element" == "true" || "$background_only" == "true" ]]
}

while IFS= read -r pid; do
  owner_uid=$(ps -p "$pid" -o uid= 2>/dev/null | tr -d ' ')
  [[ "$owner_uid" == "$current_uid" ]] || continue

  command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
  [[ "$command_line" == *.app/Contents/* ]] || continue
  bundle_path="${command_line%/Contents/*}"

  case "$bundle_path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/Library/Apple/*) continue ;;
  esac
  is_background_app "$bundle_path" || continue
  [[ -z "${seen_pids[$pid]:-}" ]] || continue

  info_plist="$bundle_path/Contents/Info.plist"
  name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist" 2>/dev/null || true)
  [[ -n "$name" ]] || name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist" 2>/dev/null || true)
  [[ -n "$name" ]] || name=$(basename "$bundle_path" .app)

  seen_pids[$pid]=1
  candidate_pids+=("$pid")
  candidate_names+=("$name")
  candidate_bundles+=("$bundle_path")
done < "$tap_output"

if (( ${#candidate_pids[@]} == 0 )); then
  echo "No third-party background input monitors were safe to restart automatically."
  exit 0
fi

echo "Found ${#candidate_pids[@]} candidate processes:"
for index in {1..${#candidate_pids[@]}}; do
  printf '  %-24s PID %s\n' "${candidate_names[$index]}" "${candidate_pids[$index]}"
done

if [[ "$mode" == "--list" ]]; then
  echo "List-only mode: no processes were restarted."
  exit 0
fi

echo "Requesting a normal exit from the background monitors…"
typeset -A relaunch_bundles
for index in {1..${#candidate_pids[@]}}; do
  pid="${candidate_pids[$index]}"
  bundle_path="${candidate_bundles[$index]}"
  if kill -TERM "$pid" 2>/dev/null; then
    echo "  Exit requested: ${candidate_names[$index]}"
    relaunch_bundles[$bundle_path]=1
  else
    echo "  Unable to stop: ${candidate_names[$index]}"
  fi
done

sleep 2
echo "Reopening the monitor applications…"
for bundle_path in ${(k)relaunch_bundles}; do
  if [[ -d "$bundle_path" ]] && open -g "$bundle_path"; then
    echo "  Opened: $(basename "$bundle_path" .app)"
  else
    echo "  Unable to open: $bundle_path"
  fi
done

sleep 2
echo "Done. No system settings were changed, and WindowServer was not restarted."
