# First, the named parameters.
{
  # you almost always want to depend on lib
  lib,
  git,

  # these are Nixpkgs functions that your package uses
  buildGoModule,
  fetchFromGitHub,

  # more dependencies would go here...
}: # this means end of named parameters

# Now, the definition of your package.
# This should be something that produces a derivation, not
# a string or a raw attribute set or anything else.
# buildGoModule is a function that returns a derivation, so
# you want `buildGoModule ...` here, not `{ pet = ...; }` here;
# the latter is an attribute set.

buildGoModule rec {
  pname = "beads";
  version = "0.59.0";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-IyO0RWP98NQ8GHVsolhu80FS06aqrZjg0JprDiFdyCk=";
  };

  vendorHash = "sha256-ygZPi56fVEHaEShGVGpObFkrLs1DHrM8i2Y4BktMmpA=";

  nativeCheckInputs = [ git ];

  preCheck = ''
    export HOME="$(mktemp -d)"
    git init .
  '';

  meta = {
    description = "Beads - A memory upgrade for your coding agent";
    homepage = "https://github.com/steveyegge/beads";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
