{
  config,
  configLib,
  pkgs,
  lib,
  ...
}:

let
  port = 3535;
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    ./backups.nix
  ];

  services.gitea = {
    enable = true; # Enable Gitea
    appName = "${config.my.domain}: Gitea Service"; # Give the site a name
    domain = "${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}";
    rootUrl = "https://${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}/"; # This is the url that gitea will use to access itself
    # settings = {
    #   DOMAIN = "${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}";
    #   ROOT_URL = "https://${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}";
    # };
    lfs = {
      enable = true;
    };
    httpPort = port;
    settings.mailer = {
      ENABLED = true;
      PROTOCOL = "smtps";
      SMTP_ADDR = config.my.smtp.host;
      SMTP_PORT = config.my.smtp.port;
      FROM = "Gitea <${config.my.smtp.from}>";
      USER = config.my.smtp.from;
    };
    mailerPasswordFile = "/run/credentials/gitea.service/smtp-password";
    # extraConfig =
    #   let
    #     docutils = pkgs.python37.withPackages (
    #       ps: with ps; [
    #         docutils # Provides rendering of ReStructured Text files
    #         pygments # Provides syntax highlighting
    #       ]
    #     );
    #   in
    #   ''
    #     [mailer]
    #     ENABLED = true
    #     FROM = "gitea@mydomain.tld"
    #     [service]
    #     REGISTER_EMAIL_CONFIRM = true
    #     [markup.restructuredtext]
    #     ENABLED = true
    #     FILE_EXTENSIONS = .rst
    #     RENDER_COMMAND = ${docutils}/bin/rst2html.py
    #     IS_INPUT_FILE = false
    #   '';
  };

  systemd.services.gitea.serviceConfig.LoadCredential = [
    "smtp-password:${config.my.smtp.passwordFile}"
  ];

  services.nginx.virtualHosts = {
    "${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}" = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
      };
    };
  };

  my.dashboard.services.gitea = {
    label = "Gitea";
    description = "Git repository manager";
    url = "https://${config.my.services.gitea.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "gitea";
  };
}
