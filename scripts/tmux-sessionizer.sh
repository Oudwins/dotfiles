#!/usr/bin/env bash

collect_project_paths() {
    local entry
    local child
    local -a parent_dirs
    local -a project_dirs
    local -a collected_paths

    if [[ -n ${CODE_PROJECTS_PARENT_DIRS:-} ]]; then
        IFS=: read -r -a parent_dirs <<< "$CODE_PROJECTS_PARENT_DIRS"
        for entry in "${parent_dirs[@]}"; do
            [[ -d $entry ]] || continue
            while IFS= read -r -d '' child; do
                collected_paths+=("$child")
            done < <(find "$entry" -mindepth 1 -maxdepth 1 -type d -print0)
        done
    fi

    if [[ -n ${CODE_PROJECTS:-} ]]; then
        IFS=: read -r -a project_dirs <<< "$CODE_PROJECTS"
        for entry in "${project_dirs[@]}"; do
            [[ -d $entry ]] || continue
            collected_paths+=("$entry")
        done
    fi

    printf '%s\n' "${collected_paths[@]}" | sort -u
}

# TODO use with droner
collect_tmux_sessions_droner() {
    local -A excluded_sessions
    local session_name
    local filter_available=0

    if [[ -n ${DRONERD_URL:-} ]]; then
        while IFS= read -r session_name; do
            [[ -n $session_name ]] || continue
            excluded_sessions["$session_name"]=1
        done < <(
            curl --silent --show-error --fail \
                --connect-timeout 0.2 \
                --max-time 0.4 \
                "$DRONERD_URL/sessions?status=running" \
            | jq -r '.sessions[].tmuxSession'
        ) && filter_available=1
    fi

    while IFS= read -r session_name; do
        [[ -n $session_name ]] || continue
        if [[ $filter_available -eq 1 && -n ${excluded_sessions["$session_name"]:-} ]]; then
            continue
        fi

        printf 'session\t%s\n' "$session_name"
    done < <(tmux list-sessions -F '#S' 2> /dev/null || true)
}

collect_tmux_sessions() {
    tmux list-sessions -F $'session\t#S' 2> /dev/null || true
}

collect_candidates() {
    local path

    collect_tmux_sessions
    while IFS= read -r path; do
        [[ -n $path ]] || continue
        printf 'path\t%s\n' "$path"
    done < <(collect_project_paths)
}

create_project_session() {
    local session_name=$1
    local project_path=$2
    local third_window_id

    tmux new-session -d -s "$session_name" -c "$project_path"
    tmux new-window -t "$session_name" -c "$project_path" > /dev/null
    third_window_id=$(tmux new-window -P -F '#{window_id}' -t "$session_name" -c "$project_path")
    tmux split-window -h -t "$third_window_id" -c "$project_path"
    tmux select-window -t "$session_name":1
}

if [[ $# -eq 1 ]]; then
    selected_type=path
    selected=$1
else
    selection=$(collect_candidates | fzf --delimiter=$'\t' --with-nth=2 --tiebreak=length,index)
    selected_type=${selection%%$'\t'*}
    selected=${selection#*$'\t'}
fi

if [[ -z $selected ]]; then
    exit 0
fi

if [[ $selected_type == session ]]; then
    if [[ -z $TMUX ]]; then
        tmux attach-session -t "$selected"
    else
        tmux switch-client -t "$selected"
    fi
    exit 0
fi

selected_name=$(basename "$selected" | tr ' .' '__')

if ! tmux has-session -t="$selected_name" 2> /dev/null; then
    create_project_session "$selected_name" "$selected"
fi

if [[ -z $TMUX ]]; then
    tmux attach-session -t "$selected_name"
else
    tmux switch-client -t "$selected_name"
fi
