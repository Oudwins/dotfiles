{
  writeShellApplication,
  writeText,
  caddy,
  jq,
  python3,
}:

let
  respond = status: {
    handler = "static_response";
    status_code = status;
  };
  config = writeText "agent-vault-router.json" (
    builtins.toJSON {
      admin = {
        disabled = true;
        config.persist = false;
      };
      apps.http.servers.router = {
        automatic_https.disable = true;
        routes = [
          {
            match = [
              {
                not = [
                  {
                    host = [
                      "127.0.0.1"
                      "localhost"
                    ];
                  }
                ];
              }
            ];
            handle = [ (respond 403) ];
            terminal = true;
          }
          {
            match = [ { header.Origin = [ "*" ]; } ];
            handle = [ (respond 403) ];
            terminal = true;
          }
          {
            match = [
              {
                path = [ "/_health" ];
                method = [
                  "GET"
                  "HEAD"
                ];
              }
            ];
            handle = [ ((respond 200) // { body = "ok\n"; }) ];
            terminal = true;
          }
        ];
      };
    }
  );
in
writeShellApplication {
  name = "agent-vault-router";
  runtimeInputs = [
    caddy
    jq
    python3
  ];
  text = ''
    # shellcheck source=/dev/null
    . "$HOME/.agent-vault/proxy.env"
    [ $# -gt 0 ] || set -- "$HOME/.config/agent-vault/config.json"
    # Later config files add to and override earlier ones, as in agent-vault-service.
    router_config=$(
      python -c '
    import os, sys
    from pathlib import Path
    from string import Template
    for path in sys.argv[1:]:
        print(Template(Path(path).read_text()).substitute(os.environ))
    ' "$@" |
      jq --slurp --slurpfile base ${config} '
        reduce .[] as $config ({}; . * $config)
        | .services | to_entries | map(
          .key as $name
          | if $name | test("^[a-z0-9]+(-[a-z0-9]+)*$") | not then error("Invalid service name: " + $name) else . end
          | (.value.target | capture("^(?<scheme>https?)://(?<authority>[^/?#@ ]+)(?<path>/[^?#]*)?(?<query>\\?[^#]*)?$") // error("Invalid target for " + $name)) as $target
          | ($target.authority + (if $target.authority | test(":[0-9]+$") then "" elif $target.scheme == "https" then ":443" else ":80" end)) as $dial
          | {
              handler: "reverse_proxy", flush_interval: -1,
              upstreams: [{dial: $dial}],
              headers: {request: {set: {Host: [$target.authority]}, delete: ["Proxy-Authorization"]}},
              transport: ({protocol: "http", compression: false, network_proxy: {from: "url", url: env.HTTP_PROXY}}
                + if $target.scheme == "https" then {tls: {ca: {provider: "file", pem_files: [env.SSL_CERT_FILE]}}} else {} end)
            } as $proxy
          # A target without a path or query exposes its whole host, so subpaths pass
          # through. Any other target is served only at its exact URL, which keeps
          # requests (including ../ tricks) inside the path its credentials cover.
          | if (($target.path // "/") == "/") and ($target.query == null) then
              {
                match: [{path: ["/" + $name, "/" + $name + "/*"]}],
                handle: [{handler: "rewrite", strip_path_prefix: ("/" + $name)}, $proxy],
                terminal: true
              }
            else
              {
                match: [{path: ["/" + $name, "/" + $name + "/"]}],
                handle: [
                  {handler: "rewrite", uri: (($target.path // "/") + ($target.query // "?") + (if $target.query then "&" else "" end) + "{http.request.uri.query}")},
                  $proxy
                ],
                terminal: true
              }
            end
        ) as $routes
        | $base[0]
        | .apps.http.servers.router.listen = ["127.0.0.1:" + (env.AGENT_VAULT_ROUTER_PORT // "28760")]
        | .apps.http.servers.router.routes += $routes + [
            {handle: [{handler: "static_response", status_code: 404}]}
          ]
      '
    )
    exec caddy run --config - <<< "$router_config"
  '';
}
