#!/bin/sh

set -eu

# Resolve this checkout instead of assuming it lives at ~/dotfiles.
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$directory"

# A common Stow directory lets packages merge their shared destinations.
# Restowing also migrates links created by the previous single-package layout.
stow --restow -d "$directory" -t "$HOME" tmx agent-skills agent-commands
