{
  writeShellApplication,
  symlinkJoin,
}:

symlinkJoin {
  name = "agent-vault-clients";
  paths =
    map
      (
        name:
        writeShellApplication {
          inherit name;
          text = ''
            proxy_env="$HOME/.agent-vault/proxy.env"
            if [ ! -r "$proxy_env" ]; then
              echo "Agent Vault is not ready; start agent-vault and agent-vault-credentials." >&2
              exit 1
            fi
            # shellcheck source=/dev/null
            . "$proxy_env"
            exec "$HOME/.npm/bin/${name}" "$@"
          '';
        }
      )
      [
        "codex"
        "claude"
        "pi"
        "opencode"
      ];
}
