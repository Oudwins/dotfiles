{
  lib,
  stdenvNoCC,
  fetchurl,
  patchelf,
  makeWrapper,
  bash,
  icu,
  openssl,
  zlib,
  stdenv,
}:

let
  # packages https://www.manager.io/releases
  pname = "manager-server";
  version = "25.12.21.3153";

  arch =
    if stdenvNoCC.hostPlatform.isAarch64 then
      "arm64"
    else if stdenvNoCC.hostPlatform.isx86_64 then
      "x64"
    else
      throw "Unsupported platform: ${stdenvNoCC.hostPlatform.system}";

  src = fetchurl {
    url = "https://github.com/Manager-io/Manager/releases/download/${version}/ManagerServer-linux-${arch}.tar.gz";
    hash = "sha256-JbdFJzFOdik2bfp6xNIOPi50Vru8YAqskSqX+a2fJ/4=";
  };

  rpath = lib.makeLibraryPath [
    stdenv.cc.cc
    icu
    openssl
    zlib
  ];
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];
  # Important: don't let generic fixups strip/patch more than we intend.
  dontStrip = true;
  dontPatchELF = true;

  unpackPhase = "true";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/${pname}"
    tar -xzf "$src" -C "$out/libexec/${pname}"

    chmod +x "$out/libexec/${pname}/ManagerServer"

    runHook postInstall
  '';

  postFixup = ''
    appDir="$out/libexec/${pname}"
    bin="$appDir/ManagerServer"

    patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$bin"
    patchelf --set-rpath "${rpath}" "$bin"

    mkdir -p "$out/bin"

    # Primary entrypoint matches upstream name
    makeWrapper "$bin" "$out/bin/ManagerServer" \
      --set ASPNETCORE_ENVIRONMENT Production \
      --set DOTNET_SYSTEM_GLOBALIZATION_INVARIANT 0 \
      --prefix LD_LIBRARY_PATH : "$appDir:${rpath}"
  '';

  meta = with lib; {
    description = "Manager.io Server Edition (ManagerServer)";
    homepage = "https://www.manager.io/server-edition";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "ManagerServer";
  };
}
