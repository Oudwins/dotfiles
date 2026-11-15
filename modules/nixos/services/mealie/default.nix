{ config, configLib, ... }:

let
  port = 9925;
  domain =
    "${config.my.services.mealie.subdomain}.${config.my.server.location}.${config.my.domain}";
in {
  imports = [ ./backup.nix (configLib.relativeToRoot "modules/nixos/services/nginx") ];

  sops.secrets."openrouter/api_key" = { };
  sops.templates."mealie-openrouter.env".content = ''
    OPENAI_API_KEY=${config.sops.placeholder."openrouter/api_key"}
  '';

  services.mealie = {
    enable = true;
    inherit port;
    listenAddress = "127.0.0.1";
    credentialsFile = config.sops.templates."mealie-openrouter.env".path;
    database.createLocally = true;
    settings = {
      BASE_URL = "https://${domain}";
      ALLOW_SIGNUP = "false";
      # AI
      OPENAI_BASE_URL = config.my.providers.openrouter.baseURL;
      OPENAI_MODEL = "openrouter/free";
      OPENAI_ENABLE_IMAGE_SERVICES = "false";
      OPENAI_ENABLE_TRANSCRIPTION_SERVICES = "false";
    };
  };

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };

  my.dashboard.services.mealie = {
    label = "Mealie";
    description = "Recipes and meal planning";
    url = "https://${domain}";
    category = "apps";
    icon = "mealie";
  };
}
