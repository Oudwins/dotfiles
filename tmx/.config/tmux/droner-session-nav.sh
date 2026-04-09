#!/usr/bin/env sh

set -u

debug() {
  tmux display-message "$1" >/dev/null 2>&1 || true
}

cleanup() {
  [ -n "${response_file-}" ] && rm -f "${response_file}" 2>/dev/null || true
  [ -n "${error_file-}" ] && rm -f "${error_file}" 2>/dev/null || true
}

response_file=
error_file=
trap cleanup EXIT

direction=${1-}
case "${direction}" in
  prev|next) ;;
  *)
    debug "droner-session-nav: invalid direction"
    exit 0
    ;;
esac

dronerd_url=${DRONERD_URL-http://localhost:57876}
dronerd_url=${dronerd_url%/}

if [ -z "${dronerd_url}" ]; then
  debug "droner-session-nav: DRONERD_URL is not set"
  exit 0
fi

current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0
encoded_session=$(printf '%s' "${current_session}" | jq -sRr @uri 2>/dev/null) || {
  debug "droner-session-nav: failed to encode current session"
  exit 0
}
url="${dronerd_url}/_session/${direction}?tmuxsession=${encoded_session}"

response_file=$(mktemp)
error_file=$(mktemp)
http_code=$(curl -sS -o "${response_file}" -w '%{http_code}' "${url}" 2>"${error_file}") || {
  curl_error=$(tr '\n' ' ' < "${error_file}")
  debug "droner-session-nav: request failed: ${curl_error}"
  exit 0
}
if [ "${http_code}" -lt 200 ] || [ "${http_code}" -ge 300 ]; then
  debug "droner-session-nav: server returned HTTP ${http_code}"
  exit 0
fi

response=$(cat "${response_file}")
target_session=$(printf '%s' "${response}" | jq -r '.sessions[0].tmuxSession // empty' 2>/dev/null) || {
  debug "droner-session-nav: failed to parse server response"
  exit 0
}

if [ -z "${target_session}" ]; then
  debug "droner-session-nav: no ${direction} session for ${current_session}"
  exit 0
fi

if [ "${target_session}" = "${current_session}" ]; then
  debug "droner-session-nav: already in ${current_session}"
  exit 0
fi

if ! tmux has-session -t "${target_session}" 2>/dev/null; then
  debug "droner-session-nav: tmux session not found: ${target_session}"
  exit 0
fi

target_window="${target_session}:1"

tmux switch-client -t "${target_window}" >/dev/null 2>&1 || {
  debug "droner-session-nav: failed to switch to ${target_window}"
  exit 0
}
