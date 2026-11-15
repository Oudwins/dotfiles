import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/bootstrap-encrypted.sh"
PASSPHRASE = "test passphrase with $shell 'characters' \\ and spaces"


class BootstrapEncryptedTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.host = self.repo / "hosts/test-host"
        self.host.mkdir(parents=True)
        (self.host / "default.nix").write_text("{}")
        self.home = self.root / "home"
        (self.home / ".ssh").mkdir(parents=True)
        self.key = self.home / ".ssh/id_ed25519"
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.key)],
            check=True,
        )
        self.public_key = self.key.with_suffix(".pub").read_text().strip()
        self.known_hosts = self.home / ".ssh/known_hosts"
        self.original_known_hosts = (
            f"other-server {self.public_key}\n"
            f"test-host-initrd {self.public_key}\n"
        )
        self.known_hosts.write_text(self.original_known_hosts)
        self.master = self.root / "master-key"
        self.master.write_text("test master key")
        self.log = self.root / "installer.json"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.write_command("git", '#!/bin/sh\nprintf "%s\\n" "$TEST_REPO"\n')
        self.write_command(
            "getent",
            '#!/bin/sh\nprintf "fixture:x:1000:1000::%s:/bin/bash\\n" "$TEST_HOME"\n',
        )
        self.write_command(
            "nix",
            """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import stat
import sys

if sys.argv[1] == "eval":
    if os.environ.get("TEST_EVAL_FAILURE"):
        sys.exit(9)
    print(os.environ["TEST_SETTINGS"])
    sys.exit(0)

assert sys.argv[1:3] == ["run", "github:nix-community/nixos-anywhere"]
args = sys.argv[3:]
def value(flag):
    return args[args.index(flag) + 1]
extra = Path(value("--extra-files"))
index = args.index("--disk-encryption-keys")
password = Path(args[index + 2])
master = extra / "etc/ssh/ssh_master_key"
host_key = extra / "etc/secrets/initrd/test-host-key"
log = {
    "args": args,
    "cwd": os.getcwd(),
    "files": sorted(str(p.relative_to(extra)) for p in extra.rglob("*") if p.is_file()),
    "passphraseMatches": password.read_text() == os.environ["TEST_PASSPHRASE"],
    "passwordMode": stat.S_IMODE(password.stat().st_mode),
    "masterMode": stat.S_IMODE(master.stat().st_mode),
    "masterMatches": master.read_text() == "test master key",
    "hostKeyMode": stat.S_IMODE(host_key.stat().st_mode),
    "hostPublicKey": host_key.with_suffix(".pub").read_text().strip(),
    "tempDir": str(password.parent),
}
Path(os.environ["TEST_LOG"]).write_text(json.dumps(log))
sys.exit(int(os.environ.get("TEST_INSTALL_EXIT", "0")))
""",
        )
        self.env = os.environ | {
            "HOME": str(self.home),
            "SUDO_USER": "",
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TMPDIR": str(self.root),
            "TEST_REPO": str(self.repo),
            "TEST_HOME": str(self.home),
            "TEST_LOG": str(self.log),
            "TEST_PASSPHRASE": PASSPHRASE,
            "TEST_SETTINGS": "/dev/test-disk\n/tmp/configured-password\n/etc/secrets/initrd/test-host-key\n2244",
        }

    def write_command(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_script(self, *, input=None, args=(), env=None, trace=False):
        if input is None:
            input = f"test-host\n{PASSPHRASE}\n{PASSPHRASE}\n"
        return subprocess.run(
            [
                "bash",
                *(["-x"] if trace else []),
                str(SCRIPT),
                "-n", "test-host",
                "-d", "root@192.0.2.10",
                "--source-master-key", str(self.master),
                *args,
            ],
            input=input,
            text=True,
            capture_output=True,
            env=self.env | (env or {}),
            cwd=self.repo,
        )

    def assert_not_installed(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.known_hosts.read_text(), self.original_known_hosts)

    def test_install_supplies_secrets_separately_and_pins_host_key(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = json.loads(self.log.read_text())
        self.assertTrue(log["passphraseMatches"])
        self.assertTrue(log["masterMatches"])
        for field in ("passwordMode", "masterMode", "hostKeyMode"):
            self.assertEqual(log[field], 0o600)
        self.assertEqual(log["files"], [
            "etc/secrets/initrd/test-host-key",
            "etc/secrets/initrd/test-host-key.pub",
            "etc/ssh/ssh_master_key",
        ])
        self.assertIn("/tmp/configured-password", log["args"])
        self.assertIn(str(self.host / "hardware-configuration.nix"), log["args"])
        self.assertEqual(log["cwd"], str(self.repo))
        self.assertFalse(Path(log["tempDir"]).exists())
        self.assertEqual(self.known_hosts.read_text(), (
            f"other-server {self.public_key}\n"
            f"test-host-initrd {log['hostPublicKey']}\n"
        ))
        self.assertIn("-p 2244 root@192.0.2.10", result.stdout)
        self.assertNotIn(PASSPHRASE, result.stdout + result.stderr)

    def test_cancel_does_not_install_or_change_trust(self):
        self.assert_not_installed(self.run_script(input="no\n"))

    def test_empty_or_mismatched_passphrases_do_not_install(self):
        for input in ("test-host\n\n\n", "test-host\none\ntwo\n"):
            with self.subTest(input=input):
                self.assert_not_installed(self.run_script(input=input))
                self.assertFalse(list(self.root.glob("tmp.*")))

    def test_configuration_failure_stops_before_install(self):
        self.assert_not_installed(self.run_script(env={"TEST_EVAL_FAILURE": "1"}))

    def test_invalid_secret_paths_do_not_install(self):
        settings = (
            "/dev/test-disk\n/etc/password\n/etc/secrets/initrd/test-host-key\n2244",
            "/dev/test-disk\n/tmp/..\n/etc/secrets/initrd/test-host-key\n2244",
            "/dev/test-disk\n/tmp/password\n/nix/store/private-key\n2244",
        )
        for value in settings:
            with self.subTest(settings=value):
                self.assert_not_installed(self.run_script(env={"TEST_SETTINGS": value}))
        self.assert_not_installed(self.run_script(args=("--target-master-key", "relative/key")))

    def test_installer_failure_cleans_up_without_changing_trust(self):
        result = self.run_script(env={"TEST_INSTALL_EXIT": "7"})
        self.assertEqual(result.returncode, 7)
        log = json.loads(self.log.read_text())
        self.assertFalse(Path(log["tempDir"]).exists())
        self.assertEqual(self.known_hosts.read_text(), self.original_known_hosts)

    def test_nested_host_directory_and_installer_port(self):
        nested = self.repo / "hosts/location/test-host"
        nested.parent.mkdir()
        self.host.rename(nested)
        result = self.run_script(args=("--port", "2525"))
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.log.read_text())["args"]
        self.assertEqual(args[args.index("--ssh-port") + 1], "2525")
        self.assertIn(str(nested / "hardware-configuration.nix"), args)

    def test_sudo_uses_callers_ssh_key_and_known_hosts(self):
        root_home = self.root / "root-home"
        result = self.run_script(env={
            "HOME": str(root_home),
            "SUDO_USER": "fixture",
            "SUDO_UID": str(os.getuid()),
            "SUDO_GID": str(os.getgid()),
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.log.read_text())["args"]
        self.assertEqual(args[args.index("-i") + 1], str(self.key))
        self.assertFalse(root_home.exists())

    def test_passphrase_is_not_exposed_by_shell_tracing(self):
        result = self.run_script(trace=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(PASSPHRASE, result.stdout + result.stderr)

    def test_quoted_home_paths_and_explicit_host_directory(self):
        custom_key = self.home / ".ssh/custom key"
        custom_key.write_text("test identity")
        result = self.run_script(args=(
            "-k", "~/.ssh/custom key",
            "--host-config-dir", "hosts/test-host",
        ))
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.log.read_text())["args"]
        self.assertEqual(args[args.index("-i") + 1], str(custom_key))

    def test_help_and_missing_option_value(self):
        self.assertEqual(self.run_script(args=("--help",)).returncode, 0)
        self.assert_not_installed(self.run_script(args=("--port",)))


if __name__ == "__main__":
    unittest.main()
