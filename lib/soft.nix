# Applies nix-secrets soft secrets to a host's `my.*` options.
# Priorities (lower number wins): option default 1500 < global 1100 < per-host 1000
# < a plain assignment in hosts/<name> (100).
{ lib, name, values }:
let
  at = priority: lib.mapAttrsRecursive (_: lib.mkOverride priority);
in
{
  my = lib.mkMerge [
    (at 1100 (values.global or { }))
    (at 1000 (values.hosts.${name} or { }))
  ];
}
