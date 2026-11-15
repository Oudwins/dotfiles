#!/usr/bin/env sh

set -eu

if [ "${1-}" != "--popup" ]; then
  tmux display-popup -E -w 70% -h 45% -T "droner new" "$0" --popup
  exit 0
fi

prompt_label="Prompt (optional): "
id_label="ID (optional): "

printf "Create droner job\n\n"
printf "%s" "${prompt_label}"
IFS= read -r droner_prompt
printf "%s" "${id_label}"
IFS= read -r droner_id

set -- droner new
if [ -n "${droner_id}" ]; then
  set -- "$@" --id "${droner_id}"
fi
if [ -n "${droner_prompt}" ]; then
  set -- "$@" --prompt "${droner_prompt}"
fi

tmux display-message "droner: running..."

if "$@"; then
  tmux display-message "droner: done"
else
  exit_code=$?
  tmux display-message "droner: failed (exit ${exit_code})"
fi
