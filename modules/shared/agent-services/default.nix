# Upstreams coding agents reach through Agent Vault's router at
# http://127.0.0.1:28760/<name>, which injects their credentials. A module
# declares its service's local endpoint and the variable that the matching
# entry in home-files/tmx/.config/agent-vault/config.json reads; a host points
# the service at another machine instead:
#
#   agentServices.llmproxy.address = "https://tubby.<tailnet>.ts.net:8317";
{
  config,
  lib,
  isDarwin,
  ...
}:

let
  services = lib.attrValues config.agentServices;
  # Agent Vault rejects IP-based service hosts, so the host must contain a letter.
  endpoint = lib.types.strMatching "https?://[A-Za-z0-9.-]*[A-Za-z][A-Za-z0-9.-]*(:[0-9]+)?(/[^?#]*)?";
  hostOf = url: builtins.head (builtins.match "https?://([^/:]+).*" url);
  localHosts = lib.filter (lib.hasSuffix ".localhost") (map (service: hostOf service.local) services);
in
{
  options.agentServices = lib.mkOption {
    default = { };
    description = "Agent services routed through Agent Vault.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          address = lib.mkOption {
            type = lib.types.nullOr endpoint;
            default = null;
            example = "https://tubby.example.ts.net:8317";
            description = "Remote endpoint to use instead of the local service, which is then disabled. Null uses `local`. Must be a hostname such as a Tailscale MagicDNS name, not an IP.";
          };
          local = lib.mkOption {
            type = endpoint;
            description = "Endpoint of the service when it runs on this machine.";
          };
          variable = lib.mkOption {
            type = lib.types.str;
            description = "Agent Vault environment variable that receives the endpoint.";
          };
        };
      }
    );
  };

  config = {
    home-manager.users.${config.my.username}.services.agent-vault = {
      environment = lib.listToAttrs (
        map (service: {
          name = service.variable;
          value = if service.address == null then service.local else service.address;
        }) services
      );
      # MagicDNS names resolve into Tailscale's CGNAT and IPv6 ranges, which
      # Agent Vault blocks unless allowlisted.
      networkAllowlist = lib.mkIf (lib.any (service: service.address != null) services) [
        "100.64.0.0/10"
        "fd7a:115c:a1e0::/48"
      ];
    };
  }
  // lib.optionalAttrs (!isDarwin) {
    networking.extraHosts = lib.concatMapStrings (host: "127.0.0.1 ${host}\n") localHosts;
  };
}
