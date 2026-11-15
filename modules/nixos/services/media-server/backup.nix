{
  config,
  pkgs,
  lib,
  ...
}:
##########
# WARNING LLM CODE
# NOT GOOD ACTUALLY
#######
let
  cfg = config.my.media_server;

  # Helper function to create backup configuration for arr services
  createArrBackup = serviceName: dataDir: {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        systemctl stop ${serviceName}

        # Create backup directory if it doesn't exist
        mkdir -p ${dataDir}/restic-backups

        # Find and backup all SQLite databases
        find ${dataDir} -name "*.db" -o -name "*.sqlite*" | while read db; do
          if [ -f "$db" ]; then
            dbname=$(basename "$db")
            ${pkgs.sqlite}/bin/sqlite3 "$db" ".dump" > "${dataDir}/restic-backups/$dbname.dump"
          fi
        done

        # Also backup config files
        if [ -d "${dataDir}/config" ]; then
          cp -r ${dataDir}/config ${dataDir}/restic-backups/
        fi

        systemctl start ${serviceName}
      '';
      paths = [ "${dataDir}/restic-backups" ];
    };
  };

  # Helper function to create restore script for arr services
  createArrRestoreScript =
    serviceName: dataDir:
    pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        sudo systemctl stop ${serviceName}

        # Restore the latest backup
        restic-${serviceName} restore --target / latest

        # Restore databases
        find ${dataDir}/restic-backups -name "*.dump" | while read dump; do
          if [ -f "$dump" ]; then
            dbname=$(basename "$dump" .dump)
            sudo rm -f "${dataDir}/$dbname"
            ${pkgs.sqlite}/bin/sqlite3 "${dataDir}/$dbname" < "$dump"
            sudo chown ${serviceName}:${serviceName} "${dataDir}/$dbname"
          fi
        done

        # Restore config if it exists
        if [ -d "${dataDir}/restic-backups/config" ]; then
          sudo rm -rf ${dataDir}/config
          sudo cp -r ${dataDir}/restic-backups/config ${dataDir}/
          sudo chown -R ${serviceName}:${serviceName} ${dataDir}/config
        fi

        # Start service back up
        sudo systemctl start ${serviceName}
      '';
    };
in
{
  config = lib.mkIf cfg.enable {
    # Jellyfin backup configuration
    # Data directory: /var/lib/jellyfin
    systemd.tmpfiles.rules = [
      "d /var/lib/jellyfin/restic-backups 700 jellyfin jellyfin -"
      "d /var/lib/jellyseerr/restic-backups 700 jellyseerr jellyseerr -"
      "d /var/lib/radarr/restic-backups 700 radarr radarr -"
      "d /var/lib/sonarr/restic-backups 700 sonarr sonarr -"
      "d /var/lib/bazarr/restic-backups 700 bazarr bazarr -"
      "d /var/lib/prowlarr/restic-backups 700 prowlarr prowlarr -"
    ];

    my.resticBackup = {
      # Jellyfin backup
      jellyfin = {
        enable = true;
        user = "root";
        healthchecks.enable = true;

        extraConfig = {
          backupPrepareCommand = ''
            systemctl stop jellyfin

            # Backup Jellyfin database and config
            if [ -f "/var/lib/jellyfin/data/jellyfin.db" ]; then
              ${pkgs.sqlite}/bin/sqlite3 /var/lib/jellyfin/data/jellyfin.db ".dump" > /var/lib/jellyfin/restic-backups/jellyfin.db.dump
            fi

            # Backup config directory
            if [ -d "/var/lib/jellyfin/config" ]; then
              cp -r /var/lib/jellyfin/config /var/lib/jellyfin/restic-backups/
            fi

            systemctl start jellyfin
          '';
          paths = [ "/var/lib/jellyfin/restic-backups" ];
        };
      };

      # Jellyseerr backup
      jellyseerr = {
        enable = true;
        user = "root";
        healthchecks.enable = true;

        extraConfig = {
          backupPrepareCommand = ''
            systemctl stop jellyseerr

            # Backup Jellyseerr database
            if [ -f "/var/lib/jellyseerr/config/db/db.sqlite3" ]; then
              ${pkgs.sqlite}/bin/sqlite3 /var/lib/jellyseerr/config/db/db.sqlite3 ".dump" > /var/lib/jellyseerr/restic-backups/db.sqlite3.dump
            fi

            # Backup entire config directory
            if [ -d "/var/lib/jellyseerr/config" ]; then
              cp -r /var/lib/jellyseerr/config /var/lib/jellyseerr/restic-backups/
            fi

            systemctl start jellyseerr
          '';
          paths = [ "/var/lib/jellyseerr/restic-backups" ];
        };
      };

      # Radarr backup
      radarr = createArrBackup "radarr" "/var/lib/radarr/.config/Radarr";

      # Sonarr backup
      sonarr = createArrBackup "sonarr" "/var/lib/sonarr/.config/NzbDrone";

      # Bazarr backup
      bazarr = createArrBackup "bazarr" "/var/lib/bazarr";

      # Prowlarr backup
      prowlarr = createArrBackup "prowlarr" "/var/lib/prowlarr";
    };

    environment.systemPackages = [
      pkgs.sqlite # required for the db commands

      # Jellyfin restore script
      (pkgs.writeShellApplication {
        name = "jellyfin-restore";
        text = ''
          sudo systemctl stop jellyfin

          # Restore the latest backup
          restic-jellyfin restore --target / latest

          # Remove existing database
          sudo rm -f /var/lib/jellyfin/data/jellyfin.db*

          # Restore database
          if [ -f "/var/lib/jellyfin/restic-backups/jellyfin.db.dump" ]; then
            ${pkgs.sqlite}/bin/sqlite3 /var/lib/jellyfin/data/jellyfin.db < /var/lib/jellyfin/restic-backups/jellyfin.db.dump
            sudo chown jellyfin:jellyfin /var/lib/jellyfin/data/jellyfin.db
          fi

          # Restore config
          if [ -d "/var/lib/jellyfin/restic-backups/config" ]; then
            sudo rm -rf /var/lib/jellyfin/config
            sudo cp -r /var/lib/jellyfin/restic-backups/config /var/lib/jellyfin/
            sudo chown -R jellyfin:jellyfin /var/lib/jellyfin/config
          fi

          sudo systemctl start jellyfin
        '';
      })

      # Jellyseerr restore script
      (pkgs.writeShellApplication {
        name = "jellyseerr-restore";
        text = ''
          sudo systemctl stop jellyseerr

          # Restore the latest backup
          restic-jellyseerr restore --target / latest

          # Remove existing database and config
          sudo rm -rf /var/lib/jellyseerr/config

          # Restore config directory (includes database)
          if [ -d "/var/lib/jellyseerr/restic-backups/config" ]; then
            sudo cp -r /var/lib/jellyseerr/restic-backups/config /var/lib/jellyseerr/
            sudo chown -R jellyseerr:jellyseerr /var/lib/jellyseerr/config
          fi

          sudo systemctl start jellyseerr
        '';
      })

      # Arr services restore scripts
      (createArrRestoreScript "radarr" "/var/lib/radarr/.config/Radarr")
      (createArrRestoreScript "sonarr" "/var/lib/sonarr/.config/NzbDrone")
      (createArrRestoreScript "bazarr" "/var/lib/bazarr")
      (createArrRestoreScript "prowlarr" "/var/lib/prowlarr")
    ];
  };
}
