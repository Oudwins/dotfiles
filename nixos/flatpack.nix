{ config, pkgs, ... }:
let
  # Apuntamos directamente a 'gnugrep' en lugar de 'grep'
  grep = pkgs.gnugrep;
  # 1. Declaramos los Flatpaks que *deseamos* en nuestro sistema
  desiredFlatpaks = [
    "app.zen_browser.zen"
  ];
in
{
  services.flatpak.enable = true;
  system.userActivationScripts.flatpakManagement = {
    text = ''
      # 2. Asegurarse de que el repositorio Flathub esté añadido
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo

      # 3. Obtener los Flatpaks actualmente instalados
      installedFlatpaks=$(${pkgs.flatpak}/bin/flatpak list --app --columns=application)

      # 4. Eliminar cualquier Flatpak que NO esté en la lista deseada
      for installed in $installedFlatpaks; do
        if ! echo ${toString desiredFlatpaks} | ${grep}/bin/grep -q $installed; then
          echo "Eliminando $installed porque no está en la lista desiredFlatpaks."
          ${pkgs.flatpak}/bin/flatpak uninstall -y --noninteractive $installed
        fi
      done

      # 5. Instalar o reinstalar los Flatpaks que SÍ queremos
      for app in ${toString desiredFlatpaks}; do
        echo "Asegurando que $app esté instalado."
        ${pkgs.flatpak}/bin/flatpak install -y flathub $app
      done

      # 6. Eliminar Flatpaks no utilizados
      ${pkgs.flatpak}/bin/flatpak uninstall --unused -y

      # 7. Actualizar todos los Flatpaks instalados
      ${pkgs.flatpak}/bin/flatpak update -y
    '';
  };
}
