import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class JustSecretsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.bin = Path(temporary.name)
        nix = self.bin / "nix"
        nix.write_text(
            "#!/usr/bin/env python3\n"
            "import json, sys\n"
            "print(json.dumps(sys.argv[1:]))\n"
        )
        nix.chmod(0o755)
        self.env = os.environ | {"PATH": f"{self.bin}:{os.environ['PATH']}"}
        self.env.pop("SECRETS", None)

    def run_just(self, *args, secrets=None):
        env = self.env.copy()
        if secrets is not None:
            env["SECRETS"] = secrets
        result = subprocess.run(
            ["just", "--justfile", str(ROOT / "justfile"), *args],
            env=env, capture_output=True, text=True, check=True,
        )
        return result.stdout

    def build_args(self, **kwargs):
        return json.loads(self.run_just("build", "tubby", **kwargs))

    def test_default_uses_pinned_secrets(self):
        self.assertNotIn("--override-input", self.build_args())

    def test_empty_path_uses_pinned_secrets(self):
        self.assertNotIn("--override-input", self.build_args(secrets=""))

    def test_checkout_path_overrides_secrets_as_one_argument(self):
        checkout = str(self.bin / "nix secrets 'with quotes' $literal")
        args = self.build_args(secrets=checkout)
        index = args.index("--override-input")
        self.assertEqual(args[index:], ["--override-input", "secrets", f"git+file://{checkout}"])

    def test_relative_checkout_path_is_made_absolute(self):
        args = self.build_args(secrets="../nix-secrets")
        self.assertEqual(args[-1], f"git+file://{ROOT.parent / 'nix-secrets'}")

    def test_editing_uses_default_checkout_without_overriding_builds(self):
        checkout = self.run_just("--evaluate", "secrets_dir")
        self.assertEqual(Path(checkout), Path.home() / "nix-secrets")

    def test_editing_uses_explicit_checkout(self):
        checkout = str(self.bin / "custom-secrets")
        command = self.run_just("--evaluate", "override", secrets=checkout)
        self.assertEqual(
            shlex.split(command),
            ["--override-input", "secrets", f"git+file://{checkout}"],
        )
        self.assertEqual(
            self.run_just("--evaluate", "secrets_dir", secrets=checkout), checkout,
        )


if __name__ == "__main__":
    unittest.main()
