#!/usr/bin/env python3
"""One-time move of leftover tmx/ files into home-files/tmx/."""

import argparse
from datetime import datetime
import filecmp
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="preview without changing files")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    old = root / "tmx"
    new = root / "home-files/tmx"
    home = Path.home().resolve()

    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments])

    if git("rev-parse", "--git-dir") != git("rev-parse", "--git-common-dir"):
        parser.error("run this from the main checkout, not a worktree")
    if old.is_symlink() or new.is_symlink() or not new.is_dir():
        parser.error("tmx/ and home-files/tmx/ must be real directories")
    if not old.exists():
        print("No leftover tmx/ directory; nothing to migrate.")
        return
    if not old.is_dir() or git("ls-files", "-z", "--", "tmx"):
        parser.error("tmx/ must be an untracked directory; update this checkout first")
    if (new / ".migration-backup").is_symlink():
        parser.error("refusing to use a symlink as the backup directory")

    backup = new / ".migration-backup" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    moves = []
    duplicates = []
    directories = []

    def plan(source, destination):
        if not destination.exists() and not destination.is_symlink():
            moves.append((source, destination))
        elif (
            source.is_symlink() and destination.is_symlink()
            and source.readlink() == destination.readlink()
        ):
            duplicates.append(source)
        elif not source.is_symlink() and not destination.is_symlink():
            if source.is_dir() and destination.is_dir():
                for child in sorted(source.iterdir()):
                    plan(child, destination / child.name)
                directories.append(source)
            elif (
                source.is_file() and destination.is_file()
                and filecmp.cmp(source, destination, shallow=False)
            ):
                duplicates.append(source)
            else:
                moves.append((source, backup / source.relative_to(old)))
        else:
            moves.append((source, backup / source.relative_to(old)))

    plan(old, new)
    links = []

    def find_links(source, target):
        if target.is_symlink():
            if Path(os.path.abspath(target.parent / target.readlink())) == source:
                links.append((target, new / source.relative_to(old)))
        elif source.is_dir() and not source.is_symlink() and target.is_dir():
            for child in sorted(source.iterdir()):
                find_links(child, target / child.name)

    for source in sorted(old.iterdir()):
        find_links(source, home / source.name)

    tracked = set(git("ls-files", "-z").split(b"\0"))
    ignore_paths = set()
    if any(backup in destination.parents for _, destination in moves):
        ignore_paths.add((backup.parent.relative_to(root).as_posix(), True))
    for source in [source for source, _ in moves] + duplicates:
        destination = new / source.relative_to(old)
        relative = destination.relative_to(root).as_posix()
        if os.fsencode(relative) not in tracked:
            entry = destination if destination.exists() or destination.is_symlink() else source
            ignore_paths.add((relative, entry.is_dir() and not entry.is_symlink()))

    patterns = []
    for relative, directory in sorted(ignore_paths):
        path = relative + ("/" if directory else "")
        ignored = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", "--", path])
        if ignored.returncode == 0:
            continue
        if ignored.returncode != 1:
            parser.error(f"could not check ignore rules for {relative}")
        if "\n" in path or "\r" in path:
            parser.error("cannot write a Git ignore pattern for a filename containing a newline")
        pattern = "/" + "".join("\\" + char if char in "\\*?[] " else char for char in path)
        patterns.append((path, pattern))
        print(f"IGNORE {path}")

    for source, destination in moves:
        print(f"MOVE {source.relative_to(root)} -> {destination.relative_to(root)}")
    for source in duplicates:
        print(f"REMOVE duplicate {source.relative_to(root)} (new copy is identical)")
    for link, destination in links:
        print(f"LINK {link} -> {destination}")
    if args.dry_run:
        return

    # Ignore local data before moving it into this public checkout's new layout.
    if patterns:
        with (root / ".gitignore").open("a") as output:
            output.write("\n# Local files moved by scripts/migrate-home-files.py\n")
            output.writelines(pattern + "\n" for _, pattern in patterns)
        for path, _ in patterns:
            result = subprocess.run(["git", "-C", str(root), "check-ignore", "-q", "--", path])
            if result.returncode:
                parser.error(f"a nested ignore rule overrides {path}; fix it before migrating")

    for source, destination in moves:
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"refusing to overwrite {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(source, destination)
    for source in duplicates:
        source.unlink()
    for directory in directories:
        directory.rmdir()
    for link, destination in links:
        link.unlink()
        link.symlink_to(os.path.relpath(destination, link.parent))
    print("Migration complete. Run ./updateSymlinks.sh to restow the tracked configs.")


if __name__ == "__main__":
    main()
