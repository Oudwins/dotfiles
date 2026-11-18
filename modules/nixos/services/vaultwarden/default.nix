{
  config,
  lib,
  pkgs,
  ...
}:

let
  host = "${config.my.services.vaultwarden.subdomain}.${config.my.server.location}.${config.my.domain}";
  wardenPort = 10000;

  # Logs location ?
in
{
  imports = [
    ./backup.nix
  ];
  sops.secrets."vaultwarden/env_file" = { };
  # TODO:
  # - Would be cool to add have I been pwned check by adding API key to config. see HaveIBeenPwned
  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden/env_file".path;
    config = {
      DOMAIN = "https://${host}";
      DATABASE_MAX_CONNS = "5";

      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = "${toString wardenPort}";
      ROCKET_WORKERS = "5";

      TRASH_AUTO_DELETE_DAYS = "180"; # 6 months
      SHOW_PASSWORD_HINT = true; # Show password hints in UI. This is ok because its not public facing.

      USER_ATTACHMENT_LIMIT = 1; # KB. Set low so we don't use this function since I'm not going to back them up.

      SMTP_HOST = config.my.smtp.host;
      SMTP_PORT = config.my.smtp.port;
      SMTP_SECURITY = "force_tls";
      SMTP_FROM = config.my.smtp.from;
      SMTP_FROM_NAME = "Vaultwarden";
      SMTP_USERNAME = config.my.smtp.from;
      SMTP_PASSWORD_FILE = "/run/credentials/vaultwarden.service/smtp-password";

      # LOG_LEVEL = "debug";
      # USE_SYSLOG=false # Not needed. But might want to add it to debug in the future
    };
  };

  systemd.services.vaultwarden.serviceConfig.LoadCredential = [
    "smtp-password:${config.my.smtp.passwordFile}"
  ];

  environment.systemPackages = with pkgs; [
    vaultwarden # installs the CLI might be useful for token generation or other things.
  ];

  services.nginx.virtualHosts."${config.my.services.vaultwarden.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString wardenPort}";
        proxyWebsockets = true; # Enable if needed
      };
    };

  my.dashboard.services.vaultwarden = {
    label = "Bitwarden";
    description = "Password manager";
    url = "https://${host}";
    category = "apps";
    icon = "vaultwarden";
  };

  my.dashboard.services.vaultwarden-admin = {
    label = "Bitwarden Admin";
    description = "Bitwarden Admin";
    url = "https://${host}/admin";
    category = "system";
    icon = "vaultwarden";
  };

}
