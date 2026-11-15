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

simulate=false
for arg in "$@"; do
	case "$arg" in -n | --no | --simulate) simulate=true ;; esac
done

# Agent entries are linked one by one into these directories, so they must be
# real directories before Stow runs; otherwise Stow could fold ~/.agents into a
# single link to the checkout and the links below would land inside the repo.
agent_destinations=("$HOME/.agents/skills" "$HOME/.claude/skills")
if ! $simulate; then
	mkdir -p "${agent_destinations[@]}"
fi

# Remove a link that points into this checkout but no longer resolves
# (left behind when files move, e.g. the old tmx/ and agent-*/ packages).
remove_if_stale() {
	local link=$1
	[ -L "$link" ] && [ ! -e "$link" ] || return 0
	case "$(realpath -m -- "$link")" in
	"$directory"/*)
		if $simulate; then echo "would remove stale link $link"; else rm -- "$link"; fi
		;;
	esac
}

# Plain-file configs: Stow package home-files/tmx mirrors $HOME.
package_root="$directory/home-files"
while IFS= read -r -d '' path; do
	target="$HOME/${path#"$package_root/tmx/"}"
	remove_if_stale "$target"
	# A real directory in $HOME may hold per-entry links for a path the package
	# provides as a single link (e.g. .config/opencode/commands).
	if [ -d "$target" ] && [ ! -L "$target" ]; then
		for child in "$target"/* "$target"/.[!.]*; do
			remove_if_stale "$child"
		done
	fi
done < <(find "$package_root/tmx" -mindepth 1 -print0)

# Let Git resolve ignore rules, including negations and nested .gitignore files.
ignore=$(
	git -C "$package_root/tmx" ls-files --others --ignored --exclude-standard --directory -z |
		perl -0ne 'chomp; s{/$}{}; push @paths, quotemeta($_);
			END { print "^(?:", join("|", @paths), ")\$" }'
)
stow --restow --ignore="$ignore" -d "$package_root" -t "$HOME" "$@" tmx

# Agent skills and commands: one link per entry, in every agent's skills dir.
for destination in "${agent_destinations[@]}"; do
	[ -d "$destination" ] || continue
	for link in "$destination"/*; do
		remove_if_stale "$link"
	done
done

declare -A seen=()
for source in "$directory"/agents/skills/*/ "$directory"/agents/commands/*/; do
	[ -d "$source" ] || continue
	source=${source%/}
	name=$(basename -- "$source")
	if [ -n "${seen[$name]:-}" ]; then
		echo "Agent entry '$name' exists in both agents/skills and agents/commands." >&2
		exit 1
	fi
	seen[$name]=1
	for destination in "${agent_destinations[@]}"; do
		target="$destination/$name"
		if [ -e "$target" ] && [ ! -L "$target" ]; then
			echo "Refusing to replace $target: it is not a symlink." >&2
			exit 1
		fi
		if $simulate; then
			[ "$(readlink -- "$target" 2>/dev/null)" = "$source" ] || echo "would link $target -> $source"
		else
			ln -sfn -- "$source" "$target"
		fi
	done
done
