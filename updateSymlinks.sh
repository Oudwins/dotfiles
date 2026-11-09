#!/usr/bin/env bash

set -euo pipefail

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
for package in tmx agent-skills agent-commands; do
	# Let Git resolve ignore rules, including negations and nested .gitignore files.
	ignore=$(
		git -C "$package" ls-files --others --ignored --exclude-standard --directory -z |
			perl -0ne 'chomp; s{/$}{}; push @paths, quotemeta($_);
				END { print "^(?:", join("|", @paths), ")\$" }'
	)
	stow --restow --ignore="$ignore" -d "$directory" -t "$HOME" "$@" "$package"
done
