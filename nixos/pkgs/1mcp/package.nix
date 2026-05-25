{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage rec {
  pname = "1mcp";
  version = "0.32.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@1mcp/agent/-/agent-${version}.tgz";
    hash = "sha512-IVeNreF9/mH4EwW3BqapXxLHUKxNdG+8yxy4yAzQlmPuP6/AnZjYg9+ufARJbq7RYj24TUBEaitfm9EiyEwXIg==";
  };

  sourceRoot = "package";
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-RnCyWOUVOU/FVfzzfl9HulSwB9xCOk4jBRKMpv2NQw0=";
  npmInstallFlags = [
    "--omit=dev"
    "--omit=optional"
  ];
  dontNpmBuild = true;

  meta = {
    description = "All-in-one MCP server aggregator and manager";
    homepage = "https://github.com/1mcp-app/agent";
    license = lib.licenses.asl20;
    mainProgram = "1mcp";
    maintainers = [ ];
  };
}
