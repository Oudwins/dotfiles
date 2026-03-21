# First, the named parameters.
{
# you almost always want to depend on lib
lib, git,

# these are Nixpkgs functions that your package uses
buildGoModule, fetchFromGitHub,

# more dependencies would go here...
}: # this means end of named parameters

# Now, the definition of your package.
# This should be something that produces a derivation, not
# a string or a raw attribute set or anything else.
# buildGoModule is a function that returns a derivation, so
# you want `buildGoModule ...` here, not `{ pet = ...; }` here;
# the latter is an attribute set.

buildGoModule rec {
  pname = "jsonc2json";
  version = "0.0.2";

  src = fetchFromGitHub {
    owner = "Oudwins";
    repo = "jsonc2json";
    rev = "${version}";
    hash = "sha256-sSTPqTTAW3YBVx7WtnrP7GgqrXsHIOY6FyeaceZGG/E=";
  };

  vendorHash = null;

  nativeCheckInputs = [ git ];

  preCheck = ''
    export HOME="$(mktemp -d)"
    git init .
  '';

  meta = {
    description = "jsonc2json - tiny cli to convert jsonc to json";
    homepage = "https://github.com/Oudwins/jsonc2json";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
