{
  lib,
  configLib ? null,
  secrets ? null,
  ...
}:
{
  # use path relative to the root of the project
  relativeToRoot = lib.path.append ../.;

  # Copy a single file from the private nix-secrets input into the store.
  # Interpolating "${secrets}/<file>" instead would make the whole secrets repo
  # (including plaintext soft secrets) part of the system closure.
  secretFile =
    rel:
    builtins.path {
      path = secrets.outPath + "/${rel}";
      name = baseNameOf rel;
    };

  # The nix-secrets source of a secretFile store path, for reading it during
  # evaluation. `nix flake check` doesn't write secretFile copies to the store,
  # so reading the copy itself fails there.
  secretSource =
    file:
    let
      sources = lib.listToAttrs (
        map (path: {
          name = builtins.unsafeDiscardStringContext (
            toString (
              builtins.path {
                inherit path;
                name = builtins.unsafeDiscardStringContext (baseNameOf path);
              }
            )
          );
          value = path;
        }) (lib.filesystem.listFilesRecursive (secrets.outPath + "/sops"))
      );
    in
    sources.${builtins.unsafeDiscardStringContext (toString file)} or file;
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory") # include directories
          || (
            (path != "default.nix") # ignore default.nix
            && (lib.strings.hasSuffix ".nix" path) # include .nix files
          )

        ) (builtins.readDir path)
      )
    );

  mod = a: b: a - (builtins.div a b) * b; # modulo operator. Usage mod a b -> a % b

  # Takes [{key1: value1}, {key2: value2}] and returns [key1, key2]
  topLevelKeysFromAttrsList = attrsList: lib.unique (lib.concatMap lib.attrNames attrsList);
  # Merges a list of attribute sets deeply. Can be used at top level of a module
  # inspired by https://gist.github.com/udf/4d9301bdc02ab38439fd64fbda06ea43
  # But doesn't seem to work
  topLevelDeepMerge =
    attrsList:
    let
      keys = configLib.topLevelKeysFromAttrsList attrsList;
      merged = lib.mapAttrs (_: v: lib.mkMerge v) (lib.foldAttrs (n: a: [ n ] ++ a) [ ] attrsList);
    in
    merged;

  hash = {
    getIntBetween = # usage: configLib.hash.getIntBetween "name" 10000 60000
      let
        hexChars = lib.listToAttrs (
          lib.imap0 (i: v: {
            name = v;
            value = i;
          }) (lib.strings.stringToCharacters "0123456789abcdef")
        );
        hexToInt = s: lib.foldl (a: b: a * 16 + hexChars."${b}") 0 (lib.strings.stringToCharacters s);
        genId =
          name: startRangeInt: endRangeInt:
          let
            # 8 hex chars = ~32 bits of entropy
            h = builtins.substring 0 8 (builtins.hashString "sha1" name);
            # Convert to int
            n = hexToInt h;
          in
          startRangeInt + (configLib.mod n endRangeInt);
      in
      genId;
  };

  networking = {
    docker = {
      # Private IP range 172.16.0.0-172.31.255.255
      getSubnet =
        networkName:
        let
          id1 = configLib.hash.getIntBetween "${networkName}_1" 0 255;
        in
        "172.20.${toString id1}.0/24";
    };
    getPort = networkName: configLib.hash.getIntBetween "${networkName}_port" 20000 39999; # k8s uses 30000–39999. I expanded a bit to avoid conflicts
  };

  users = {
    genId = username: configLib.hash.getIntBetween username 10000 60000;
    filterOutMissingGroups =
      config: groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
  };

}
