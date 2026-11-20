# Links shown on the Glance dashboard. Service modules add their own entry to
# my.dashboard.services; servers (modules/nixos/services/dashboard) and
# workstations (modules/home/common/dashboard) serve the resulting settings.
# The module only declares options, so NixOS and home-manager can both import it.
{ config, lib, ... }:

let
  inherit (lib) mkOption types escapeXML;
  # Also the order categories appear in.
  categories = [
    "apps"
    "agents"
    "media"
    "management"
    "system"
  ];
  services = lib.attrValues config.my.dashboard.services;

  # The CDN URLs Glance uses for its di: (dashboard-icons) and mdi: prefixes.
  icon =
    name:
    let
      mdi = lib.removePrefix "mdi-" name;
    in
    if mdi != name then
      ''<img class="monitor-site-icon flat-icon" src="https://cdn.jsdelivr.net/npm/@mdi/svg@latest/svg/${mdi}.svg" alt="" loading="lazy">''
    else
      ''<img class="monitor-site-icon" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/${name}.svg" alt="" loading="lazy">'';

  # The whole tile is the link.
  tile = service: ''
    <a class="monitor-site flex items-center gap-15" href="${escapeXML service.url}" target="_blank" rel="noreferrer">
      ${lib.optionalString (service.icon != "") (icon service.icon)}
      <div class="grow min-width-0">
        <div class="size-h3 color-highlight text-truncate">${escapeXML service.label}</div>
        <div class="text-truncate" title="${escapeXML service.description}">${escapeXML service.description}</div>
      </div>
    </a>
  '';

  # Glance's monitor widget markup (templates/monitor.html) with the
  # description in place of the status line, so there are no status checks.
  widget = category: {
    type = "html";
    source = ''
      <div class="widget widget-type-monitor">
        <div class="widget-header"><h2 class="uppercase">${category}</h2></div>
        <div class="widget-content">
          <ul class="dynamic-columns list-gap-20 list-with-separator">
            ${lib.concatMapStrings tile (
              lib.sort (a: b: lib.toLower a.label < lib.toLower b.label) (
                lib.filter (service: service.category == category) services
              )
            )}
          </ul>
        </div>
      </div>
    '';
  };
in
{
  options.my.dashboard = {
    services = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            # A dashboard-icons name (https://dashboardicons.com), or "mdi-<name>"
            # for Material Design Icons.
            icon = mkOption {
              type = types.str;
              default = "";
            };
            label = mkOption { type = types.str; };
            url = mkOption { type = types.str; };
            description = mkOption {
              type = types.str;
              default = "";
            };
            category = mkOption { type = types.enum categories; };
          };
        }
      );
      default = { };
    };

    settings = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "Glance settings (theme and pages) rendering my.dashboard.services; the server block is left to the host.";
    };
  };

  config.my.dashboard.settings = {
    theme = {
      # Tailwind stone-900 / stone-300, a dark stone theme.
      background-color = "24 10 10";
      primary-color = "30 6 75";
      contrast-multiplier = 1.1;
    };
    pages = [
      {
        name = "Services";
        # One column so narrow windows scroll instead of switching columns via
        # Glance's mobile bottom bar; split-column sits widgets side by side
        # when there is room.
        columns = [
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                max-columns = 2;
                widgets = map widget (
                  lib.filter (category: lib.any (service: service.category == category) services) categories
                );
              }
            ];
          }
        ];
      }
    ];
  };
}
