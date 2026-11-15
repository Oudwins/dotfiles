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
  config = writeText "executor-router.json" (
    builtins.toJSON {
      admin = {
        disabled = true;
        config.persist = false;
      };
      apps.http.servers.executor = {
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
  name = "executor-router";
  runtimeInputs = [
    caddy
    jq
    python3
  ];
  text = ''
    # shellcheck source=/dev/null
    . "$HOME/.agent-vault/proxy.env"
    exec caddy run --config - < <(
      python -c '
    import os, sys
    from pathlib import Path
    from string import Template
    print(Template(Path(sys.argv[1]).read_text()).substitute(os.environ))
    ' "''${1:-$HOME/.config/agent-vault/config.json}" |
      jq --slurpfile base ${config} '
        .services | to_entries | map(
          .key as $name
          | if $name | test("^[a-z0-9]+(-[a-z0-9]+)*$") | not then error("Invalid service name: " + $name) else . end
          | (.value.target | capture("^(?<scheme>https?)://(?<authority>[^/?#@ ]+)(?<path>/[^?#]*)?(?<query>\\?[^#]*)?$") // error("Invalid target for " + $name)) as $target
          | ($target.authority + (if $target.authority | test(":[0-9]+$") then "" elif $target.scheme == "https" then ":443" else ":80" end)) as $dial
          | {
              match: [{path: ["/" + $name, "/" + $name + "/"]}],
              handle: [
                {handler: "rewrite", uri: (($target.path // "/") + ($target.query // "?") + (if $target.query then "&" else "" end) + "{http.request.uri.query}")},
                {
                  handler: "reverse_proxy", flush_interval: -1,
                  upstreams: [{dial: $dial}],
                  headers: {request: {set: {Host: [$target.authority]}, delete: ["Proxy-Authorization"]}},
                  transport: ({protocol: "http", compression: false, network_proxy: {from: "url", url: env.HTTP_PROXY}}
                    + if $target.scheme == "https" then {tls: {ca: {provider: "file", pem_files: [env.SSL_CERT_FILE]}}} else {} end)
                }
              ],
              terminal: true
            }
        ) as $routes
        | $base[0]
        | .apps.http.servers.executor.listen = ["127.0.0.1:" + (env.EXECUTOR_ROUTER_PORT // "28760")]
        | .apps.http.servers.executor.routes += $routes + [
            {handle: [{handler: "static_response", status_code: 404}]}
          ]
      '
    )
  '';
}
