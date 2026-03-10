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

if [[ $# -eq 1 ]]; then
    selected_type=path
    selected=$1
else
    selection=$(collect_candidates | fzf --delimiter=$'\t' --with-nth=2 --tiebreak=index)
    selected_type=${selection%%$'\t'*}
    selected=${selection#*$'\t'}
fi

if [[ -z $selected ]]; then
    exit 0
fi

if [[ $selected_type == session ]]; then
    if [[ -z $TMUX ]]; then
        tmux attach -t "$selected"
    else
        tmux switch-client -t "$selected"
    fi
    exit 0
fi

selected_name=$(basename "$selected" | tr ' .' '__')
tmux_running=$(pgrep tmux)

if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s "$selected_name" -c "$selected"
    exit 0
fi

if ! tmux has-session -t="$selected_name" 2> /dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
fi

if [[ -z $TMUX ]]; then
    tmux attach -t "$selected_name"
else
    tmux switch-client -t "$selected_name"
fi
