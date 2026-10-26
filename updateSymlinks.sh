#!/bin/sh

set -eu

# Resolve this checkout instead of assuming it lives at ~/dotfiles.
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$directory"

# Worktrees are temporary; links into them break once they are removed.
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
	echo "Run this from the main checkout, not a git worktree." >&2
	exit 1
fi

# A common Stow directory lets packages merge their shared destinations.
# Restowing also migrates links created by the previous single-package layout.
stow --restow -d "$directory" -t "$HOME" tmx agent-skills agent-commands
