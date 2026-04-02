#!/usr/bin/env sh

set -eu

direction=${1-}
case "${direction}" in
  prev|next) ;;
  *) exit 0 ;;
esac

current_session=$(tmux display-message -p '#S')
encoded_session=$(printf '%s' "${current_session}" | jq -sRr @uri)
url="${DRONERD_URL}/_session/${direction}?tmuxsession=${encoded_session}"

response=$(curl -fsS "${url}") || exit 0
target_session=$(printf '%s' "${response}" | jq -r '.sessions[0].tmuxSession // empty')

[ -n "${target_session}" ] || exit 0
[ "${target_session}" != "${current_session}" ] || exit 0

if tmux has-session -t="${target_session}" 2>/dev/null; then
  tmux switch-client -t "${target_session}"
fi
