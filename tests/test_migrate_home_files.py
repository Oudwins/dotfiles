import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class MigrateHomeFilesTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles-migrate-")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / "home"
        self.root = self.home / "dotfiles"
        (self.root / "scripts").mkdir(parents=True)
        (self.root / "home-files/tmx").mkdir(parents=True)
        self.env = os.environ | {
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        checkout = Path(__file__).resolve().parents[1]
        shutil.copy2(checkout / "scripts/migrate-home-files.py", self.root / "scripts")
        shutil.copy2(checkout / "updateSymlinks.sh", self.root)
        shutil.copy2(checkout / ".gitignore", self.root)
        self.git("init", "--quiet")

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", *args], cwd=self.root, env=self.env, check=check,
            capture_output=True, text=True,
        )

    def write(self, path, content="config\n", tracked=False):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        if tracked:
            self.git("add", "--force", "--", path)

    def migrate(self, *args):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/migrate-home-files.py"), *args],
            cwd=self.home, env=self.env, capture_output=True, text=True,
        )

    def test_moves_local_data_repairs_links_and_backs_up_conflicting_settings(self):
        self.write("home-files/tmx/.config/settings.json", tracked=True)
        self.write("home-files/tmx/.local/bin/tool", tracked=True)
        self.write("tmx/.config/app/credentials", "local credentials\n")
        self.write("tmx/.local/share/app/state", "local state\n")
        (self.home / ".config").symlink_to("dotfiles/tmx/.config")
        (self.home / ".local").symlink_to("dotfiles/tmx/.local")
        (self.home / ".t3/userdata").mkdir(parents=True)
        for name in ("client-settings.json", "keybindings.json", "settings.json"):
            self.write(f"home-files/tmx/.t3/userdata/{name}", tracked=True)
            self.write(f"tmx/.t3/userdata/{name}", "old local settings\n")
            (self.home / f".t3/userdata/{name}").symlink_to(
                f"../../dotfiles/tmx/.t3/userdata/{name}"
            )

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "tmx").exists())
        self.assertEqual((self.home / ".config/app/credentials").read_text(), "local credentials\n")
        self.assertEqual((self.home / ".local/share/app/state").read_text(), "local state\n")
        for path in (".config", ".local"):
            self.assertEqual(
                (self.home / path).resolve(), (self.root / "home-files/tmx" / path).resolve()
            )
        backups = list((self.root / "home-files/tmx/.migration-backup").iterdir())
        self.assertEqual(len(backups), 1)
        for name in ("client-settings.json", "keybindings.json", "settings.json"):
            self.assertEqual((self.home / f".t3/userdata/{name}").read_text(), "config\n")
            self.assertEqual((backups[0] / f".t3/userdata/{name}").read_text(), "old local settings\n")
        self.assertEqual(
            self.git("ls-files", "--others", "--exclude-standard", "--", "home-files/tmx").stdout,
            "",
        )
        restow = subprocess.run(
            [str(self.root / "updateSymlinks.sh")], cwd=self.home, env=self.env,
            capture_output=True, text=True,
        )
        self.assertEqual(restow.returncode, 0, restow.stderr)
        self.assertEqual((self.home / ".config/app/credentials").read_text(), "local credentials\n")
        self.assertEqual(self.migrate().returncode, 0)

    def test_dry_run_does_not_change_files_ignores_or_links(self):
        self.write("home-files/tmx/.config/settings.json", tracked=True)
        self.write("tmx/.config/settings.json", "old settings\n")
        self.write("tmx/.config/app/credentials", "local credentials\n")
        link = self.home / ".config"
        link.symlink_to("dotfiles/tmx/.config")
        ignores = (self.root / ".gitignore").read_bytes()

        result = self.migrate("--dry-run")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("IGNORE", result.stdout)
        self.assertIn("MOVE", result.stdout)
        self.assertIn("LINK", result.stdout)
        self.assertEqual(os.readlink(link), "dotfiles/tmx/.config")
        self.assertEqual((link / "settings.json").read_text(), "old settings\n")
        self.assertEqual((link / "app/credentials").read_text(), "local credentials\n")
        self.assertEqual((self.root / ".gitignore").read_bytes(), ignores)
        self.assertFalse((self.root / "home-files/tmx/.migration-backup").exists())

    def test_identical_tracked_files_are_deduplicated_without_becoming_ignored(self):
        self.write("home-files/tmx/settings.json", tracked=True)
        self.write("tmx/settings.json")

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "tmx").exists())
        self.assertEqual((self.root / "home-files/tmx/settings.json").read_text(), "config\n")
        self.assertFalse((self.root / "home-files/tmx/.migration-backup").exists())
        self.assertEqual(self.git("check-ignore", "-q", "home-files/tmx/settings.json", check=False).returncode, 1)

    def test_existing_untracked_duplicates_and_conflicts_are_also_ignored(self):
        self.write("home-files/tmx/same.json", "same secret\n")
        self.write("tmx/same.json", "same secret\n")
        self.write("home-files/tmx/different.json", "new secret\n")
        self.write("tmx/different.json", "old secret\n")

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "home-files/tmx/different.json").read_text(), "new secret\n")
        self.assertEqual(
            self.git("ls-files", "--others", "--exclude-standard", "--", "home-files/tmx").stdout,
            "",
        )

    def test_generated_ignore_patterns_treat_filenames_literally(self):
        self.write("home-files/tmx/.config/demo/config.json", tracked=True)
        name = "token [1] #?!*\\secret.json "
        path = f"home-files/tmx/.config/demo/{name}"
        self.write(f"tmx/.config/demo/{name}", "secret\n")

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / path).read_text(), "secret\n")
        self.assertEqual(self.git("check-ignore", "-q", "--", path).returncode, 0)
        self.assertEqual(
            self.git("check-ignore", "-q", "--", "home-files/tmx/.config/demo/other.json", check=False).returncode,
            1,
        )

    def test_does_not_follow_destination_or_source_symlinks(self):
        outside = self.home / "outside"
        outside.mkdir()
        (outside / "keep").write_text("outside data\n")
        (self.root / "home-files/tmx/destination").symlink_to(outside)
        self.write("tmx/destination/secret", "local secret\n")
        (self.root / "tmx/source").symlink_to(outside)

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((outside / "keep").read_text(), "outside data\n")
        self.assertFalse((outside / "secret").exists())
        self.assertEqual((self.root / "home-files/tmx/source").readlink(), outside)
        self.assertEqual((self.root / "home-files/tmx/destination").readlink(), outside)
        backup = next((self.root / "home-files/tmx/.migration-backup").iterdir())
        self.assertEqual((backup / "destination/secret").read_text(), "local secret\n")

    def test_unrelated_home_links_are_not_replaced(self):
        self.write("tmx/.config/secret", "local secret\n")
        outside = self.home / "outside"
        outside.mkdir()
        (self.home / ".config").symlink_to(outside)

        result = self.migrate()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".config").readlink(), outside)
        self.assertEqual((self.root / "home-files/tmx/.config/secret").read_text(), "local secret\n")

    def test_refuses_to_migrate_files_still_tracked_in_the_old_layout(self):
        self.write("tmx/settings.json", tracked=True)

        result = self.migrate()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("update this checkout first", result.stderr)
        self.assertTrue((self.root / "tmx/settings.json").exists())


if __name__ == "__main__":
    unittest.main()
