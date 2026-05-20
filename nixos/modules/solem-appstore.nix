{ config, pkgs, lib, ... }:

# SOLEM APPSTORE — Flatpak + Flathub remote, opt-in.
#
# Single responsibility: SOLO orchestrare Flatpak system-wide + aggiungere
# remote Flathub. Niente lista app preinstallate hardcoded (resta scelta
# utente via GUI/CLI).
#
# Flathub è 100% FOSS-friendly; tutte le app sono FOSS o freeware
# (l'utente sceglie). Costo: 0 €.
#
# CLI: `flatpak install flathub <id>` o GUI tramite "GNOME Software"
# (opzionale, deve essere abilitato dal desktop module).

let
  cfg = config.solem.appstore;
in {
  options.solem.appstore = {
    enable = lib.mkEnableOption "Flatpak + Flathub remote (app store FOSS-friendly)";

    addFlathub = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Aggiungi remote Flathub al primo boot";
    };

    gnomeSoftware = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa GNOME Software (GUI store, ~200MB)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    # XDG portals richiesti per sandbox Flatpak
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    environment.systemPackages = lib.mkIf cfg.gnomeSoftware [
      pkgs.gnome-software
    ];

    # Aggiungi Flathub al primo boot
    systemd.services.solem-flathub-init = lib.mkIf cfg.addFlathub {
      description = "SOLEM — registra remote Flathub";
      after = [ "flatpak-system-helper.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "solem-flathub-init" ''
          set -euo pipefail
          ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists \
            flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        '';
        Restart = "no";
      };
    };
  };
}
