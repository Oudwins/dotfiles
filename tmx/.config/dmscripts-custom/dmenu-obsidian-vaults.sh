#!/bin/sh
# LAUNCHER
DMENU=${DMENU:-dmenu}

# List of parent directories to search. This comes from CODE_PROJECT_DIRS env variable defined in home.nix
IFS=':' read -r -a PARENT_DIRS <<< "$OBSIDIAN_VAULT_DIRS"

# Find direct child directories in the specified parent directories
directories=""
for dir in "${PARENT_DIRS[@]}"; do
    directories+=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf "%P\t$dir\n" 2>/dev/null)
    directories+=$'\n'  # Add a newline between parent directories
done
# Use dmenu to fuzzy find and select a directory
selected=$(echo "$directories" | $DMENU -i -l 15 -p "Select directory:")

if [ -n "$selected" ]; then
    # Extract the child directory name
     child_dir=$(echo "$selected" | cut -f1)
    
    # Encoding path
    #encoded_path=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$full_path")
    #xdg-open "obsidian://open?path=$encoded_path"
    #echo "$encoded_path"
    #obsidian "obsidian://open?path=$encoded_path"
    obsidian "obsidian://open?vault=$child_dir"
fi
