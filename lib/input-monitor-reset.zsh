#!/bin/zsh

# SPDX-License-Identifier: MIT
# Detect and restart current-user, third-party background Quartz Event Tap owners.

set -u

language="${1:-en}"
shift || true
mode="${1:-restart}"

if [[ "$language" == "zh" ]]; then
  usage_text=$'用法：\n  双击或直接运行：发现并重启所有检测到的第三方后台输入监听\n  --list：只列出候选进程，不重启\n  --help：显示本说明'
  unknown_argument="未知参数"
  runtime_missing="系统缺少 /usr/bin/ruby，无法读取 Event Tap 列表。"
  discovering="正在发现第三方输入监听…"
  read_failed="无法读取 Quartz Event Tap 列表。"
  none_found="未发现可安全自动重启的第三方后台输入监听。"
  found_label="发现"
  candidate_label="个候选进程"
  list_only="只列出，未重启任何进程。"
  stopping="正在正常退出这些后台监听…"
  stopped_label="已通知退出"
  stop_failed_label="无法退出"
  reopening="正在重新打开监听应用…"
  opened_label="已打开"
  open_failed_label="无法打开"
  completed="完成。本脚本未修改系统设置，也未重启 WindowServer。"
else
  usage_text=$'Usage:\n  Double-click or run directly: discover and restart all detected third-party background input monitors\n  --list: list candidates without restarting them\n  --help: show this help'
  unknown_argument="Unknown argument"
  runtime_missing="The system is missing /usr/bin/ruby, so the Event Tap list cannot be read."
  discovering="Discovering third-party input monitors…"
  read_failed="Unable to read the Quartz Event Tap list."
  none_found="No third-party background input monitors were safe to restart automatically."
  found_label="Found"
  candidate_label="candidate processes"
  list_only="List-only mode: no processes were restarted."
  stopping="Requesting a normal exit from the background monitors…"
  stopped_label="Exit requested"
  stop_failed_label="Unable to stop"
  reopening="Reopening the monitor applications…"
  opened_label="Opened"
  open_failed_label="Unable to open"
  completed="Done. No system settings were changed, and WindowServer was not restarted."
fi

if [[ "$mode" == "--help" || "$mode" == "-h" ]]; then
  print -r -- "$usage_text"
  exit 0
fi

if [[ "$mode" != "restart" && "$mode" != "--list" ]]; then
  echo "$unknown_argument: $mode"
  exit 2
fi

ruby_runtime="/usr/bin/ruby"
if [[ ! -x "$ruby_runtime" ]]; then
  echo "$runtime_missing"
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

echo "$discovering"
if ! "$ruby_runtime" "$inspector_source" > "$tap_output"; then
  echo "$read_failed"
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
  echo "$none_found"
  exit 0
fi

echo "$found_label ${#candidate_pids[@]} $candidate_label:"
for index in {1..${#candidate_pids[@]}}; do
  printf '  %-24s PID %s\n' "${candidate_names[$index]}" "${candidate_pids[$index]}"
done

if [[ "$mode" == "--list" ]]; then
  echo "$list_only"
  exit 0
fi

echo "$stopping"
typeset -A relaunch_bundles
for index in {1..${#candidate_pids[@]}}; do
  pid="${candidate_pids[$index]}"
  bundle_path="${candidate_bundles[$index]}"
  if kill -TERM "$pid" 2>/dev/null; then
    echo "  $stopped_label: ${candidate_names[$index]}"
    relaunch_bundles[$bundle_path]=1
  else
    echo "  $stop_failed_label: ${candidate_names[$index]}"
  fi
done

sleep 2
echo "$reopening"
for bundle_path in ${(k)relaunch_bundles}; do
  if [[ -d "$bundle_path" ]] && open -g "$bundle_path"; then
    echo "  $opened_label: $(basename "$bundle_path" .app)"
  else
    echo "  $open_failed_label: $bundle_path"
  fi
done

sleep 2
echo "$completed"
