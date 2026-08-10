#!/bin/zsh

script_dir="${0:A:h}"
exec "$script_dir/lib/input-monitor-reset.zsh" en "$@"
