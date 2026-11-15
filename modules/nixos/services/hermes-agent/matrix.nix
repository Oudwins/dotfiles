{ config, lib, ... }:

let
  matrixHost = config.my.hermes-agent.matrix.homeserver;
in
{
  options.my.hermes-agent.matrix = {
    homeserver = lib.mkOption {
      type = lib.types.str;
      default = "https://matrix.${config.my.server.location}.${config.my.domain}";
    };

    userId = lib.mkOption {
      type = lib.types.str;
      default = "@hermes:${lib.removePrefix "https://" matrixHost}";
    };

    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    allowedRooms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    homeRoom = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  config = {
    services.hermes-agent = {
      environment = {
        MATRIX_HOMESERVER = matrixHost;
        MATRIX_USER_ID = config.my.hermes-agent.matrix.userId;
        MATRIX_REQUIRE_MENTION = "true";
        MATRIX_SESSION_SCOPE = "auto";
        MATRIX_AUTO_THREAD = "true";
      }
      // lib.optionalAttrs (config.my.hermes-agent.matrix.allowedUsers != [ ]) {
        MATRIX_ALLOWED_USERS = lib.concatStringsSep "," config.my.hermes-agent.matrix.allowedUsers;
      }
      // lib.optionalAttrs (config.my.hermes-agent.matrix.allowedRooms != [ ]) {
        MATRIX_ALLOWED_ROOMS = lib.concatStringsSep "," config.my.hermes-agent.matrix.allowedRooms;
      }
      // lib.optionalAttrs (config.my.hermes-agent.matrix.homeRoom != null) {
        MATRIX_HOME_ROOM = config.my.hermes-agent.matrix.homeRoom;
      };

      extraDependencyGroups = [ "matrix" ];
    };
  };
}
