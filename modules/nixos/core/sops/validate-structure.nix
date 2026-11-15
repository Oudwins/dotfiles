{ config, lib, configLib, ... }:

let
  secretNames = lib.attrNames config.sops.secrets;

  getSopsFile = name:
    config.sops.secrets.${name}.sopsFile or config.sops.defaultSopsFile;

  sopsFiles = lib.unique (map getSopsFile secretNames);

  readSopsFile = file:
    let
      source = configLib.secretSource file;
    in
    if builtins.pathExists source then
      builtins.readFile source
    else
      null;

  stripYamlQuotes = value:
    lib.removeSuffix "'" (lib.removePrefix "'"
      (lib.removeSuffix "\"" (lib.removePrefix "\"" value)));

  yamlPaths = text:
    let
      lines = lib.splitString "\n" text;
      parseLine = line:
        let
          match = builtins.match "^([[:space:]]*)([^[:space:]#-][^:]*):.*$" line;
          key = stripYamlQuotes (lib.trim (builtins.elemAt match 1));
        in
        # sops-nix reads "a/b" as nested keys, so a literal "a/b" key can never
        # satisfy a secret; skip it rather than let it match by name.
        if match == null || lib.hasInfix "/" key then
          null
        else
          {
            indent = builtins.stringLength (builtins.elemAt match 0);
            inherit key;
          };

      step = state: line:
        let
          parsed = parseLine line;
        in
        if parsed == null then
          state
        else
          let
            parents = lib.filter (item: item.indent < parsed.indent) state.stack;
            stack = parents ++ [ parsed ];
            path = lib.concatStringsSep "/" (map (item: item.key) stack);
          in
          {
            inherit stack;
            paths = state.paths ++ [ path ];
          };
    in
    (lib.foldl' step { stack = [ ]; paths = [ ]; } lines).paths;

  sopsFileData = lib.listToAttrs (map
    (file: {
      name = builtins.unsafeDiscardStringContext (toString file);
      value = readSopsFile file;
    })
    sopsFiles);

  secretExists = name:
    let
      file = builtins.unsafeDiscardStringContext (toString (getSopsFile name));
      data = sopsFileData.${file};
    in
    data != null && builtins.elem name (yamlPaths data);

  missingFiles = lib.filter
    (file: sopsFileData.${builtins.unsafeDiscardStringContext (toString file)} == null)
    sopsFiles;

  displayPath = file: builtins.unsafeDiscardStringContext (toString file);

  missingSecrets = lib.filter
    (name: !(secretExists name))
    secretNames;
in
{
  config = lib.mkIf (config.my.sops.enable or false) {
    assertions = [
      {
        assertion = missingFiles == [ ];
        message = ''
          Missing SOPS files:

          ${lib.concatMapStringsSep "\n" (file: "- ${displayPath file}") missingFiles}
        '';
      }
      {
        assertion = missingSecrets == [ ];
        message = ''
          Missing SOPS secrets referenced by config.sops.secrets:

          ${lib.concatMapStringsSep "\n" (name: "- ${name} in ${displayPath (getSopsFile name)}") missingSecrets}
        '';
      }
    ];
  };
}
