{
  writeShellApplication,
  symlinkJoin,
  coreutils,
  curl,
}:

let
  proxyVariables = [
    "HTTP_PROXY"
    "HTTPS_PROXY"
    "NO_PROXY"
    "http_proxy"
    "https_proxy"
    "no_proxy"
    "NODE_USE_ENV_PROXY"
    "SSL_CERT_FILE"
    "CODEX_CA_CERTIFICATE"
    "NODE_EXTRA_CA_CERTS"
    "REQUESTS_CA_BUNDLE"
    "CURL_CA_BUNDLE"
    "GIT_SSL_CAINFO"
    "DENO_CERT"
    "AGENT_VAULT_HEALTH_URL"
    # Placeholder from config.json's environment, only valid through the vault.
    "GH_TOKEN"
  ];
in
symlinkJoin {
  name = "agent-vault-clients";
  paths =
    builtins.concatMap
      (name: [
        (writeShellApplication {
          inherit name;
          text = ''
            vault_unavailable() {
              echo "Agent Vault is not ready; check agent-vault and agent-vault-credentials." >&2
              echo "Use ${name}-unwrapped to run without Agent Vault." >&2
              exit 1
            }

            proxy_env="$HOME/.agent-vault/proxy.env"
            [ -r "$proxy_env" ] || vault_unavailable
            # shellcheck source=/dev/null
            . "$proxy_env"
            [ -n "''${AGENT_VAULT_HEALTH_URL:-}" ] || vault_unavailable
            ${curl}/bin/curl --noproxy '*' --fail --silent --output /dev/null --max-time 2 \
              "''${AGENT_VAULT_HEALTH_URL:-}" || vault_unavailable
            exec "$HOME/.npm/bin/${name}" "$@"
          '';
        })
        (writeShellApplication {
          name = "${name}-unwrapped";
          # Also bypass a parent agent's inherited proxy and CA settings.
          text = ''
            exec ${coreutils}/bin/env ${
              builtins.concatStringsSep " " (map (variable: "-u ${variable}") proxyVariables)
            } \
              "$HOME/.npm/bin/${name}" "$@"
          '';
        })
      ])
      [
        "codex"
        "claude"
        "pi"
        "opencode"
      ];
}
