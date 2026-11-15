{ config, configLib, pkgs, lib, ... }:

let
  serviceName = "acc";
  # Tailscale hostname for the container (will appear in your tailnet)
  tailscaleHostname = "${config.my.server.location}${serviceName}";
  # The domain that host nginx expects for the Manager.io virtualhost
  managerDomain =
    "${config.my.services.manager.subdomain}.${config.my.server.location}.${config.my.domain}";
  # Data directory for persistent storage
  dataDir = "${config.my.services.baseDataDir}/${serviceName}";
  # Tailscale image - use a stable version
  # Tags: https://hub.docker.com/r/tailscale/tailscale/tags
  tailscaleImage = "tailscale/tailscale:stable";
  # Nginx image
  nginxImage = "nginx:alpine";
  # Container names (used for --network=container:NAME reference)
  tailscaleContainerName = "${serviceName}_tailscale";
  nginxContainerName = "${serviceName}_nginx";

  #######################################
  # Architecture:
  #
  # [Tailscale Network]
  #        |
  #        v (HTTP on port 80)
  # [Tailscale Container] <-- Nginx shares this network namespace
  #        |
  # [Nginx Container] (listens on port 80)
  #        |
  #        v (HTTPS on port 443, Host: ${managerDomain})
  # [Host Nginx] --> [Manager.io service]
  #######################################
in {

  imports = [ (configLib.relativeToRoot "modules/nixos/services/containers") ];

  # Create data directories
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${dataDir}/tailscale 0755 root root -"
  ];

  # Write nginx config - proxies to host's nginx on port 443
  environment.etc."${serviceName}/nginx.conf".text = ''
    events {
      worker_connections 1024;
    }

    http {
      server {
        listen 80;
        server_name _;

        location / {
          # Proxy to host's nginx on port 443 with the Manager.io domain
          # Using 172.30.0.1 (Docker gateway from default-address-pools)
          proxy_pass https://host.docker.internal:443;
          proxy_http_version 1.1;

          # Set Host header so host nginx routes to the correct virtualhost
          proxy_set_header Host ${managerDomain};

          # SSL settings for upstream connection
          proxy_ssl_verify off;
          proxy_ssl_server_name on;

          # Standard proxy headers
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # WebSocket support
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        }
      }
    }
  '';

  # Allow Docker containers to reach host nginx
  networking.firewall.interfaces."docker0".allowedTCPPorts = [ 443 ];

  virtualisation.oci-containers.containers = {
    # Tailscale container - joins tailnet and provides network namespace
    "${tailscaleContainerName}" = {
      image = tailscaleImage;
      autoStart = true;
      hostname = tailscaleHostname;

      extraOptions = [
        "--pull=always" # pull always so always keep stable version
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
        "--device=/dev/net/tun:/dev/net/tun"
        "--add-host=host.docker.internal:host-gateway"
      ];

      environment = {
        TS_AUTHKEY = "file:/run/secrets/tailscale_auth_key";
        TS_STATE_DIR = "/var/lib/tailscale";
        TS_HOSTNAME = tailscaleHostname;
        TS_EXTRA_ARGS = "--accept-routes";
      };

      volumes = [
        "${dataDir}/tailscale:/var/lib/tailscale"
        # Use existing tailscale auth key secret
        "${
          config.sops.secrets."tailscale/auth_key".path
        }:/run/secrets/tailscale_auth_key:ro"
      ];
    };

    # Nginx container - shares network with Tailscale, proxies to host
    "${nginxContainerName}" = {
      image = nginxImage;
      autoStart = true;

      extraOptions = [
        # Share network namespace with tailscale container
        # (inherits host.docker.internal from tailscale container)
        "--network=container:${tailscaleContainerName}"
      ];

      volumes = [ "/etc/${serviceName}/nginx.conf:/etc/nginx/nginx.conf:ro" ];

      dependsOn = [ tailscaleContainerName ];
    };
  };
}
