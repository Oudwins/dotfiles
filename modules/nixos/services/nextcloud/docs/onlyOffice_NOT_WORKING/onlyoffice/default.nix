{
  config,
  lib,
  pkgs,
  ...
}:
let
  # You have to manually go into the nextcloud UI and connect to the onlyoffice server using the ts.net domain and http (https not working)
  # serviceName = lib.last (lib.splitString "/" (builtins.toString ./.)); # Parent directory name
  # subdomain = "office.${config.networking.hostName}";

  # serveConfig = builtins.toJSON {
  #   TCP."443".HTTPS = true;
  #   # Web."${subdomain}.${config.my.domain}:443".Handlers."/".Proxy = "http://127.0.0.1:80";
  #   Web = {
  #     "*.ts.net".Handlers."/".Proxy = "http://127.0.0.1:80";
  #     "*.${config.my.domain}".Handlers."/".Proxy = "http://127.0.0.1:80";
  #   };
  # };
  # configPath = pkgs.writeTextDir "tailscale-serve.json" serveConfig;
in
{
  # sops.secrets."container/${serviceName}/jwt-secret" = { };
  # sops.secrets."onlyoffice/jwt_secret_env" = { };

  # virtualisation.oci-containers.containers = {
  #   ${serviceName} = {
  #     image = "onlyoffice/documentserver@sha256:b9e3c35eab182d3de822a53b109b0f27070f6eacea3b1388b9c50d1182f638f2";
  #     environmentFiles = [
  #       # Contains "JWT_SECRET=<token>"
  #       config.sops.secrets."onlyoffice/jwt_secret_env".path
  #     ];
  #   };
  #   "tailscale-${serviceName}" = {
  #     environment.TS_HOSTNAME = subdomain;
  #     volumes = [ "${configPath}:/config" ];
  #   };
  # };
  # This starts the service correctly and /healthcheck and integration with nextcloud works but when I try to open a document I get an error
  # sops.secrets."onlyoffice/jwt_secret_env" = {
  #   # owner = "docker";
  # };

  # #https://forum.onlyoffice.com/t/nextcloud-onlyoffice-the-document-could-not-be-saved/5438/7
  # virtualisation.docker.enable = true;
  # virtualisation.oci-containers = {
  #   backend = "docker";
  #   containers = {
  #     onlyoffice = {
  #       # autoStart = true;
  #       image = "onlyoffice/documentserver@sha256:b9e3c35eab182d3de822a53b109b0f27070f6eacea3b1388b9c50d1182f638f2";
  #       #image = "onlyoffice/documentserver:8.2";
  #       environmentFiles = [
  #         # Contains "JWT_SECRET=<token>"
  #         config.sops.secrets."onlyoffice/jwt_secret_env".path
  #       ];
  #       ports = [ "8087:80" ];
  #       # volumes = [
  #       #   "/var/www/onlyoffice:/var/www/onlyoffice"
  #       #   "/var/log/onlyoffice:/var/log/onlyoffice"
  #       #   "/var/lib/onlyoffice:/var/lib/onlyoffice"
  #       #   "/usr/share/fonts:/usr/share/fonts"
  #       # ];
  #     };
  #   };
  # };

  # services.nginx.virtualHosts."${config.my.services.onlyoffice.subdomain}.${config.my.globalSubdomain}.${config.my.domain}" = {
  #   #enableACME = true;
  #   #forceSSL = true;
  #   useACMEHost = "${config.my.globalSubdomain}.${config.my.domain}";
  #   addSSL = true;
  #   locations."/" = {
  #     proxyPass = "http://localhost:8087";
  #     proxyWebsockets = true; # Enable if needed
  #   };
  # };

  # This shows the main page in localhost:8081 but then the /healthcheck fails with 502 Bad Gateway error from nginx
  # sops.secrets."onlyoffice/jwt_secret" = {
  #   # owner = "docker";
  # };
  # services.onlyoffice = {
  #   enable = true;
  #   hostname = "${config.my.services.onlyoffice.subdomain}.${config.my.globalSubdomain}.${config.my.domain}";
  #   port = 8081;
  #   jwtSecretFile = config.sops.secrets."onlyoffice/jwt_secret".path;
  # };
  # services.nginx.virtualHosts."${config.my.services.onlyoffice.subdomain}.${config.my.globalSubdomain}.${config.my.domain}" = {
  #   useACMEHost = "${config.my.globalSubdomain}.${config.my.domain}";
  #   addSSL = true;
  #   listen = [{
  #     addr = "127.0.0.1";
  #     port = 8081;
  #   }];
  # };
}
