# VM test of modules/nixos/services/artifacts: RustFS with its provisioning,
# the upload server and the nginx site, with `artifact publish` uploading to the
# site's /_upload/ through a stand-in for Agent Vault's router (an nginx
# location adding the token). Run from the repo root:
#
#   nix build -L --impure --expr 'import ./tests/artifacts.nix { }'
{
  flake ? builtins.getFlake (toString ../.),
  system ? "x86_64-linux",
}:

let
  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    overlays = builtins.attrValues flake.outputs.overlays;
  };
  inherit (pkgs) lib;
  configLib = import ../lib {
    inherit lib;
    inherit (flake.inputs) secrets;
  };
  host = "artifacts.r.test";
  token = "test-upload-token";
  artifactsSecret = "test-artifacts-secret";
  # The shared secrets file, encrypted to a throwaway age key.
  testSecrets =
    pkgs.runCommand "artifacts-test-secrets"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.sops
        ];
      }
      ''
            mkdir $out
            age-keygen -o $out/key.txt 2>/dev/null
            cat > artifacts.yaml <<'EOF'
        artifacts:
          token: ${token}
          rustfs-secret-key: ${artifactsSecret}
          rustfs-env: |
            RUSTFS_ACCESS_KEY=test-root
            RUSTFS_SECRET_KEY=test-root-secret
        EOF
            sops encrypt --age "$(age-keygen -y $out/key.txt)" artifacts.yaml > $out/artifacts.yaml
      '';
in
pkgs.testers.runNixOSTest {
  name = "artifacts";
  # runNixOSTest already uses this pkgs, overlays included.
  node = {
    specialArgs = {
      inherit (flake) inputs;
      inherit configLib;
    };
  };

  nodes.machine = {
    imports = [
      ../modules/shared/my.nix
      ../modules/nixos/services/artifacts
      flake.inputs.sops-nix.nixosModules.sops
    ];
    # Declared by roles/server on real hosts.
    options.my.server.location = lib.mkOption { type = lib.types.str; };
    config = {
      my.domain = "test";
      my.server.location = "r";
      virtualisation.memorySize = 2048;

      # sops-nix won't read a key from the store, so it's installed to /etc first.
      environment.etc."sops-test-key.txt".source = "${testSecrets}/key.txt";
      system.activationScripts.setupSecrets.deps = [ "etc" ];
      sops.age.keyFile = "/etc/sops-test-key.txt";
      sops.age.sshKeyPaths = [ ];
      sops.gnupg.sshKeyPaths = [ ];
      sops.secrets =
        lib.genAttrs [ "artifacts/rustfs-env" "artifacts/rustfs-secret-key" "artifacts/token" ]
          (_: {
            sopsFile = lib.mkForce "${testSecrets}/artifacts.yaml";
          });
      # Run the scanner, which applies lifecycle expiry, every second.
      services.rustfs.settings = {
        RUSTFS_SCANNER_CYCLE = "1";
        RUSTFS_SCANNER_START_DELAY_SECS = "1";
        RUSTFS_DATA_USAGE_UPDATE_DIR_CYCLES = "1";
      };
      # Covers provisioning a bucket without a policy or lifecycle rules.
      services.rustfs.buckets.private = { };

      # No certificates in the test: serve the site over plain HTTP.
      services.nginx.virtualHosts.${host} = {
        useACMEHost = lib.mkForce null;
        addSSL = lib.mkForce false;
      };
      # Stands in for Agent Vault's router, which adds the token and forwards
      # to the artifacts site (agents.artifacts in roles/agents.nix).
      services.nginx.virtualHosts.router = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 28760;
          }
        ];
        locations."/artifacts/" = {
          proxyPass = "http://127.0.0.1/";
          extraConfig = ''
            proxy_set_header Host ${host};
            proxy_set_header Authorization "Bearer ${token}";
            client_max_body_size 0;
          '';
        };
      };

      environment.systemPackages = [ pkgs.artifact ];
      environment.variables = {
        ARTIFACT_UPLOAD_URL = "http://127.0.0.1:28760/artifacts/_upload";
        ARTIFACT_PUBLIC_URL = "https://${host}";
      };
    };
  };

  testScript = ''
    import re

    machine.wait_for_unit("artifact-upload.service")
    machine.wait_for_open_port(8095)
    machine.wait_for_open_port(80)

    def get(path, expect=200):
        out = machine.succeed(
            f"curl -s -o /tmp/body -w '%{{http_code}} %{{content_type}}' -H 'Host: ${host}' http://127.0.0.1{path}"
        )
        status, _, content_type = out.partition(" ")
        assert int(status) == expect, f"GET {path}: {out}"
        return machine.succeed("cat /tmp/body"), content_type

    with subtest("the upload server rejects requests without the token"):
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT --data x http://127.0.0.1:8095/x/index.html")
        assert status == "401", status
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Authorization: Bearer wrong' --data x http://127.0.0.1:8095/x/index.html")
        assert status == "401", status
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT --data x -H 'Host: ${host}' http://127.0.0.1/_upload/x/index.html")
        assert status == "401", f"PUT to the site's /_upload/ without the token: {status}"
        # nginx refuses on the declared length, before reading any body.
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT --data x -H 'Content-Length: 300000000' -H 'Host: ${host}' http://127.0.0.1/_upload/x/big.bin || true")
        assert status == "413", f"oversized PUT to the site's /_upload/: {status}"
        status = machine.succeed("curl -s --path-as-is -o /dev/null -w '%{http_code}' -X PUT -H 'Authorization: Bearer ${token}' --data x http://127.0.0.1:8095/x/../y")
        assert status == "400", status

    with subtest("a directory is published and served"):
        machine.succeed(
            "mkdir -p /tmp/Site/sub /tmp/Site/.git",
            "echo '<h1>Report</h1>' > /tmp/Site/index.html",
            "echo 'body{}' > /tmp/Site/style.css",
            "echo 'sub page' > '/tmp/Site/sub/a page.html'",
            "echo secret > /tmp/Site/.env",
            "echo secret > /tmp/Site/.git/config",
        )
        url = machine.succeed("artifact publish /tmp/Site").strip()
        match = re.fullmatch(r"https://${host}/(site-[0-9a-f]{8})/", url)
        assert match, url
        site = match.group(1)

        body, content_type = get(f"/{site}/")
        assert "<h1>Report</h1>" in body and content_type.startswith("text/html"), (body, content_type)
        body, content_type = get(f"/{site}/style.css")
        assert content_type.startswith("text/css"), content_type
        body, _ = get(f"/{site}/sub/a%20page.html")
        assert "sub page" in body, body
        for hidden in [".env", ".git/config"]:
            get(f"/{site}/{hidden}", expect=404)

    def publish(path, id=None):
        flag = f"-id {id} " if id else ""
        url = machine.succeed(f"artifact publish {flag}{path}").strip()
        return url.removeprefix("https://${host}/").split("/")[0]

    with subtest("a single file is published at its own name, and -id replaces it"):
        machine.succeed("echo one > /tmp/notes.html")
        url = machine.succeed("artifact publish /tmp/notes.html").strip()
        match = re.fullmatch(r"https://${host}/(notes-[0-9a-f]{8})/notes.html", url)
        assert match, url
        notes = match.group(1)
        machine.succeed("echo two > /tmp/notes.html")
        assert publish("/tmp/notes.html", notes) == notes
        body, _ = get(f"/{notes}/notes.html")
        assert body.strip() == "two", body

    with subtest("only generated IDs are accepted, so agents can't share one by name"):
        machine.fail("artifact publish -id notes /tmp/notes.html")
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT --data x http://127.0.0.1:28760/artifacts/_upload/notes/notes.html")
        assert status == "400", f"PUT with an invented ID through the router: {status}"
        get("/notes/notes.html", expect=404)

    with subtest("nothing can enumerate or change artifacts anonymously"):
        get("/", expect=404)
        get(f"/{notes}/missing.html", expect=404)
        status = machine.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' -X PUT --data x -H 'Host: ${host}' http://127.0.0.1/{site}/index.html")
        assert status == "403", f"PUT through the site: {status}"
        listing = machine.succeed("curl -s -w ' %{http_code}' http://127.0.0.1:9000/artifacts/")
        assert listing.endswith(" 403"), f"anonymous bucket listing: {listing}"
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -X PUT --data x http://127.0.0.1:9000/artifacts/anon.html")
        assert status == "403", f"anonymous PUT: {status}"

    # Objects are public, so reading them with the key is allowed anyway.
    with subtest("the upload server's key can write but not list or delete"):
        machine.succeed("RC_CONFIG_DIR=/tmp/rc rc alias set up http://127.0.0.1:9000 artifacts ${artifactsSecret}")
        machine.succeed("echo x > /tmp/x.txt && RC_CONFIG_DIR=/tmp/rc rc put /tmp/x.txt up/artifacts/x.txt")
        machine.fail("RC_CONFIG_DIR=/tmp/rc rc object list up/artifacts")
        machine.fail(f"RC_CONFIG_DIR=/tmp/rc rc object remove up/artifacts/{site}/index.html")
        get(f"/{site}/")

    with subtest("provisioning can run again"):
        machine.succeed("systemctl restart rustfs-provision.service")
        machine.succeed("systemctl restart artifact-upload.service")
        machine.wait_for_open_port(8095)
        publish("/tmp/notes.html", notes)

    # Last, since jumping the clock expires everything uploaded before.
    with subtest("files expire 180 days after their last upload"):
        machine.succeed(
            "mkdir -p /tmp/stale /tmp/fresh",
            "echo stale > /tmp/stale/index.html",
            "echo fresh > /tmp/fresh/index.html",
        )
        stale = publish("/tmp/stale")
        fresh = publish("/tmp/fresh")
        machine.succeed("date -s @$(( $(date +%s) + 179 * 86400 ))")
        get(f"/{stale}/")
        publish("/tmp/fresh", fresh)
        machine.succeed("date -s @$(( $(date +%s) + 2 * 86400 ))")
        machine.wait_until_succeeds(
            f"test $(curl -s -o /dev/null -w '%{{http_code}}' -H 'Host: ${host}' http://127.0.0.1/{stale}/) = 404",
            timeout=120,
        )
        # Deleted from disk, not just hidden.
        machine.wait_until_succeeds(f"test -e /var/lib/rustfs/artifacts/{fresh} && test ! -e /var/lib/rustfs/artifacts/{stale}", timeout=120)
        body, _ = get(f"/{fresh}/")
        assert body.strip() == "fresh", body
  '';
}
