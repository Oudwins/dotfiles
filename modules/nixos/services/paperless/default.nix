{
  config,
  pkgs,
  ...
}@args:
{
  imports = [
    ./backup.nix
  ];

  sops.secrets."paperless/admin_pass" = {
    owner = "paperless";
  };

  # DATA DIR is actually -> /var/lib/paperless
  services.paperless = {
    enable = true;
    consumptionDirIsPublic = true;
    #address = "${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}";
    port = 58080;
    user = "paperless";

    # No config to set this but the username = admin
    passwordFile = config.sops.secrets."paperless/admin_pass".path;

    openMPThreadingWorkaround = true; # this fixes some bug I don't get

    settings = {
      # This says that paperless will try to OCR the document in english and spanish
      PAPERLESS_OCR_LANGUAGE = "eng+spa";
      # Only perform OCR if the document does not have text
      PAPERLESS_OCR_MODE = "skip";
      # Skip creating a copy of documents that already have text
      #PAPERLESS_OCR_SKIP_ARCHIVE_FILE = "with_text";

      # This allows us to import digitally signed documents. Otherwise it errors
      PAPERLESS_OCR_USER_ARGS = {
        "invalidate_digital_signatures" = true;
      };

      # SECURITY
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}";
      PAPERLESS_ALLOWED_HOSTS = "https://${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}";
      CORS_ALLOWED_HOSTS = "https://${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}";
    };
  };

  # Set up SSL + Domain
  services.nginx.virtualHosts."${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:58080";
        proxyWebsockets = true; # Enable if needed
      };
    };

  # Adds to the dashboard
  my.dashboard.services.paperless = {
    label = "Paperless";
    description = "Document management system";
    url = "https://${config.my.services.paperless.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "paperless-ngx";
  };
}
