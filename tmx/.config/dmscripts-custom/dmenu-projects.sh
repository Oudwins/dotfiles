#!/bin/sh
# LAUNCHER
DMENU=${DMENU:-dmenu}
EDITOR=${CODE_EDITOR:-code}

# List of parent directories to search. This comes from CODE_PROJECT_DIRS env variable defined in home.nix
IFS=':' read -r -a PARENT_DIRS <<< "$CODE_PROJECT_DIRS"

# Command to run in the selected directory
RUN_COMMAND="cd"

# Find direct child directories in the specified parent directories
directories=""
for dir in "${PARENT_DIRS[@]}"; do
    directories+=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf "%P\t$dir\n" 2>/dev/null)
    directories+=$'\n'  # Add a newline between parent directories
done

# Use dmenu to fuzzy find and select a directory
selected=$(echo "$directories" | $DMENU -i -l 15 -p "Select directory:")

if [ -n "$selected" ]; then
    # Extract the child directory name and parent directory
    child_dir=$(echo "$selected" | cut -f1)
    parent_dir=$(echo "$selected" | cut -f2)
    
    # Construct the full path of the selected directory
    full_path="$parent_dir/$child_dir"
    
    # Run the command in the selected directory
    $RUN_COMMAND "$full_path"
    $EDITOR .
fi
