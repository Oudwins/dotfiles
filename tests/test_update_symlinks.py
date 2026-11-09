import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class UpdateSymlinksTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles-stow-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "dotfiles"
        self.home = Path(temporary.name) / "home"
        self.root.mkdir()
        self.home.mkdir()
        self.env = os.environ | {
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        checkout = Path(__file__).resolve().parents[1]
        shutil.copy2(checkout / "updateSymlinks.sh", self.root)
        for package in ("tmx", "agent-skills", "agent-commands"):
            (self.root / package).mkdir()
        self.git("init", "--quiet")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, env=self.env, check=True,
            capture_output=True, text=True,
        )

    def write(self, path, content="config\n", tracked=False):
        destination = self.root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content)
        if tracked:
            self.git("add", "--force", "--", path)

    def update(self, *args):
        return subprocess.run(
            [str(self.root / "updateSymlinks.sh"), *args], cwd=self.home,
            env=self.env, capture_output=True, text=True,
        )

    def assert_link(self, path, source):
        target = self.home / path
        self.assertTrue(target.is_symlink(), str(target))
        self.assertEqual(target.resolve(), (self.root / source).resolve())

    def test_ignored_cache_does_not_conflict_with_local_cache(self):
        self.write(".gitignore", "tmx/.claude/cache/\n")
        self.write("tmx/.claude/cache/gateway-models.json", "source cache\n")
        self.write("tmx/.claude/settings.json", tracked=True)
        local_cache = self.home / ".claude/cache/gateway-models.json"
        local_cache.parent.mkdir(parents=True)
        local_cache.write_text("local cache\n")

        result = self.update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(local_cache.read_text(), "local cache\n")
        self.assertFalse(local_cache.is_symlink())
        self.assert_link(".claude/settings.json", "tmx/.claude/settings.json")

    def test_git_exceptions_and_untracked_nonignored_files_are_stowed(self):
        self.write(
            ".gitignore",
            "tmx/.config/demo/*\n!tmx/.config/demo/config.json\n",
        )
        self.write("tmx/.config/demo/config.json")
        self.write("tmx/.config/demo/secret [1] #$+.json")
        self.write("tmx/.config/demo/cache/generated.json")
        (self.home / ".config/demo").mkdir(parents=True)

        result = self.update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_link(".config/demo/config.json", "tmx/.config/demo/config.json")
        self.assertFalse((self.home / ".config/demo").is_symlink())
        self.assertFalse((self.home / ".config/demo/secret [1] #$+.json").exists())
        self.assertFalse((self.home / ".config/demo/cache").exists())

    def test_ignores_are_package_specific(self):
        self.write(".gitignore", "tmx/.agents/shared.json\n")
        self.write("tmx/.agents/shared.json", "ignored\n")
        self.write("agent-skills/.agents/shared.json", tracked=True)
        self.write("agent-commands/.agents/command.json", tracked=True)
        (self.home / ".agents").mkdir()

        result = self.update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_link(".agents/shared.json", "agent-skills/.agents/shared.json")
        self.assert_link(".agents/command.json", "agent-commands/.agents/command.json")

    def test_existing_directory_links_preserve_nix_managed_files(self):
        self.write(".gitignore", "tmx/.config/alacritty/\n")
        self.write("nix-store/config", "Nix-managed settings\n")
        generated_target = self.root / "nix-store/config"
        for path in (
            "tmx/.config/alacritty/alacritty.toml",
            "tmx/.config/gtk-3.0/settings.ini",
        ):
            source = self.root / path
            source.parent.mkdir(parents=True, exist_ok=True)
            source.symlink_to(generated_target)
        self.git("add", "--force", "--", "tmx/.config/alacritty/alacritty.toml")
        (self.home / ".config").symlink_to("../dotfiles/tmx/.config")

        result = self.update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".config").readlink(), Path("../dotfiles/tmx/.config"))
        for path in ("alacritty/alacritty.toml", "gtk-3.0/settings.ini"):
            self.assertEqual((self.home / ".config" / path).readlink(), generated_target)
            self.assertEqual((self.home / ".config" / path).read_text(), "Nix-managed settings\n")

    def test_tracked_files_inside_ignored_directories_remain_stowed(self):
        self.write(".gitignore", "tmx/.config/demo/\n")
        self.write("tmx/.config/demo/config.json", tracked=True)
        self.write("tmx/.config/demo/cache.json")
        (self.home / ".config/demo").mkdir(parents=True)

        for _ in range(2):
            result = self.update()
            self.assertEqual(result.returncode, 0, result.stderr)

        self.assert_link(".config/demo/config.json", "tmx/.config/demo/config.json")
        self.assertFalse((self.home / ".config/demo/cache.json").exists())

    def test_nested_git_and_stow_ignores_still_apply(self):
        self.write("tmx/.gitignore", "nested-cache/\n")
        self.write("tmx/nested-cache/generated.json")
        self.write(".git/info/exclude", "agent-skills/generated/\n")
        self.write("agent-skills/generated/cache.json")
        self.write("tmx/.stow-local-ignore", "^/stow-only$\n", tracked=True)
        self.write("tmx/stow-only", tracked=True)
        self.write("tmx/settings.json", tracked=True)

        result = self.update()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "nested-cache").exists())
        self.assertFalse((self.home / "generated").exists())
        self.assertFalse((self.home / "stow-only").exists())
        self.assert_link("settings.json", "tmx/settings.json")

    def test_nonignored_conflicts_still_preserve_local_files(self):
        self.write("tmx/settings.json", tracked=True)
        local_settings = self.home / "settings.json"
        local_settings.write_text("local settings\n")

        result = self.update()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("conflicts", result.stderr)
        self.assertEqual(local_settings.read_text(), "local settings\n")
        self.assertFalse(local_settings.is_symlink())

    def test_simulation_does_not_create_links(self):
        self.write("tmx/settings.json", tracked=True)

        result = self.update("--simulate")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "settings.json").exists())


if __name__ == "__main__":
    unittest.main()
