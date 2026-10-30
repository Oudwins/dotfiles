import json
import os
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import unittest
from unittest.mock import call, patch


HERE = Path(__file__).parent
RUNTIME = "/private/var/run/cli-proxy-api"


class RamDiskTests(unittest.TestCase):
    def run_helper(self):
        with patch("sys.argv", ["ramdisk.py", RUNTIME]):
            runpy.run_path(str(HERE / "ramdisk.py"), run_name="__main__")

    def test_create_and_mount_only_ram(self):
        with (
            patch("os.makedirs"),
            patch("os.path.islink", return_value=False),
            patch("os.path.ismount", return_value=False),
            patch("subprocess.check_output", return_value="/dev/disk9\n") as output,
            patch("subprocess.run") as run,
        ):
            self.run_helper()
        output.assert_called_once_with(
            ["/usr/bin/hdiutil", "attach", "-nomount", "ram://65536"], text=True
        )
        self.assertEqual(run.call_args_list[0].args[0][-1], "/dev/disk9")
        self.assertEqual(
            run.call_args_list[1].args[0],
            [
                "/sbin/mount",
                "-t",
                "hfs",
                "-o",
                "owners,nodev,nosuid,noexec,nobrowse",
                "/dev/disk9",
                RUNTIME,
            ],
        )

    def test_reuse_ram_but_refuse_persistent_volumes(self):
        for source, allowed in [("ram://65536", True), ("/data/image.dmg", False)]:
            with self.subTest(source=source):
                info = plistlib.dumps(
                    {
                        "images": [
                            {
                                "image-path": source,
                                "system-entities": [{"mount-point": RUNTIME}],
                            }
                        ]
                    }
                )
                with (
                    patch("os.makedirs"),
                    patch("os.path.islink", return_value=False),
                    patch("os.path.ismount", return_value=True),
                    patch("subprocess.check_output", return_value=info),
                    patch("subprocess.run") as run,
                ):
                    if allowed:
                        self.run_helper()
                        run.assert_called_once_with(
                            [
                                "/sbin/mount",
                                "-u",
                                "-o",
                                "owners,nodev,nosuid,noexec,nobrowse",
                                RUNTIME,
                            ],
                            check=True,
                        )
                    else:
                        with self.assertRaises(SystemExit):
                            self.run_helper()
                        run.assert_not_called()

    def test_detach_on_format_failure(self):
        with (
            patch("os.makedirs"),
            patch("os.path.islink", return_value=False),
            patch("os.path.ismount", return_value=False),
            patch("subprocess.check_output", return_value="/dev/disk9\n"),
            patch(
                "subprocess.run", side_effect=[OSError("format failed"), None]
            ) as run,
        ):
            with self.assertRaises(OSError):
                self.run_helper()
            self.assertEqual(
                run.call_args_list[-1],
                call(["/usr/bin/hdiutil", "detach", "/dev/disk9"], check=False),
            )

    def test_refuse_symlink(self):
        with (
            patch("os.makedirs"),
            patch("os.path.islink", return_value=True),
            patch("subprocess.check_output") as output,
        ):
            with self.assertRaises(SystemExit):
                self.run_helper()
            output.assert_not_called()


class PrivilegeTests(unittest.TestCase):
    def test_drop_groups_gid_uid_then_exec_with_clean_environment(self):
        account = type("Account", (), {"pw_gid": 493, "pw_uid": 493})()
        with (
            patch(
                "sys.argv",
                ["run-as-user.py", "_cliproxyapi", "/state", "/bin/proxy", "--login"],
            ),
            patch("pwd.getpwnam", return_value=account),
            patch("os.environ", {"SOPS_AGE_KEY": "must-not-be-inherited"}),
            patch("resource.setrlimit") as limit,
            patch("os.setgroups") as groups,
            patch("os.setgid") as gid,
            patch("os.setuid") as uid,
            patch("os.execve") as execute,
        ):
            order = unittest.mock.Mock()
            for name, mock in [
                ("groups", groups),
                ("gid", gid),
                ("uid", uid),
                ("exec", execute),
            ]:
                order.attach_mock(mock, name)
            runpy.run_path(str(HERE / "run-as-user.py"), run_name="__main__")
        self.assertEqual(
            [c[0] for c in order.mock_calls], ["groups", "gid", "uid", "exec"]
        )
        groups.assert_called_once_with([])
        self.assertEqual(limit.call_args.args[1], (0, 0))
        gid.assert_called_once_with(493)
        uid.assert_called_once_with(493)
        self.assertEqual(
            execute.call_args.args[:2], ("/bin/proxy", ["/bin/proxy", "--login"])
        )
        self.assertNotIn("SOPS_AGE_KEY", execute.call_args.args[2])

    def test_refuse_root_target(self):
        account = type("Account", (), {"pw_uid": 0})()
        with (
            patch("sys.argv", ["run-as-user.py", "root", "/state", "/bin/proxy"]),
            patch("pwd.getpwnam", return_value=account),
            patch("os.setgroups") as groups,
        ):
            with self.assertRaises(SystemExit):
                runpy.run_path(str(HERE / "run-as-user.py"), run_name="__main__")
            groups.assert_not_called()


class MergeTests(unittest.TestCase):
    def setUp(self):
        source = (HERE / "default.nix").read_text()
        self.merge = re.search(r"eval-all '(.+?)' \"", source, re.S).group(1)
        self.validate = re.search(
            r"eval-all --exit-status '(.+?)' \"", source, re.S
        ).group(1)
        self.base = {
            "api-keys": {
                "codex": [
                    {
                        "name": "openai",
                        "base-url": "https://api.openai.com/v1",
                        "models": [{"name": "test-model"}],
                    }
                ]
            },
            "access": {"api-keys": ["placeholder"]},
        }

    def evaluate(self, expression, overrides, *options):
        return subprocess.run(
            [os.environ.get("YQ", "yq"), "eval-all", *options, expression, "-"],
            input=json.dumps(self.base) + "\n---\n" + json.dumps(overrides),
            text=True,
            capture_output=True,
        )

    def test_named_groups_keep_models_and_add_keys(self):
        overrides = {
            "api-keys": {
                "codex": [
                    {"name": "second", "keys": [{"api-key": "test-second"}]},
                    {"name": "openai", "keys": [{"api-key": "test-key"}]},
                ]
            },
            "access": {"api-keys": ["test-client"]},
        }
        result = self.evaluate(self.merge, overrides, "-o=json")
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads(result.stdout)
        groups = {g["name"]: g for g in merged["api-keys"]["codex"]}
        self.assertEqual(groups["openai"]["models"], [{"name": "test-model"}])
        self.assertEqual(groups["openai"]["keys"], [{"api-key": "test-key"}])
        self.assertIn("second", groups)
        self.assertEqual(merged["access"]["api-keys"], ["test-client"])

    def test_null_groups_do_not_remove_base(self):
        result = self.evaluate(self.merge, {"api-keys": None}, "-o=json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), self.base)

    def test_oauth_directory_uses_private_persistent_state(self):
        source = (HERE / "default.nix").read_text()
        expression = re.search(
            r"\| \$\{lib.getExe pkgs.yq-go\} '([^']+)' >", source
        ).group(1)
        result = subprocess.run(
            [os.environ.get("YQ", "yq"), "-o=json", expression, "-"],
            input=json.dumps({"oauth": {"auth-dir": "/run/old-auth"}}),
            text=True,
            capture_output=True,
            env={**os.environ, "WRITABLE_PATH": "/var/lib/cli-proxy-api"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout)["oauth"]["auth-dir"],
            "/var/lib/cli-proxy-api/auth",
        )
        self.assertIn('"$WRITABLE_PATH/auth"', source)

    def test_reject_duplicate_and_empty_names(self):
        for names in [["openai", "openai"], [""], [None]]:
            with self.subTest(names=names):
                result = self.evaluate(
                    self.validate,
                    {
                        "api-keys": {"codex": [{"name": name} for name in names]},
                    },
                    "--exit-status",
                )
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
