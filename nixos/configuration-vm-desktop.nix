{ config, pkgs, lib, ... }:

# CONFIGURAZIONE VM DESKTOP — boot in desktop Hyprland grafico.
# Differenza da vm-minimal: enable solem.desktop = vedi UI Wayland.

{
  imports = [
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    ./modules/solem-desktop.nix          # Hyprland Wayland desktop
    ./modules/solem-plymouth.nix         # Boot splash branding
    ./modules/solem-default-apps.nix     # Firefox, Nautilus, mpv, kate, ecc.
    ./modules/solem-localhost-setup.nix  # CLI solem-localhost
    ./modules/solem-unified-cli.nix      # CLI solem dispatcher
    ./modules/solem-welcome-wizard.nix   # Wizard primo login
    ./modules/solem-demo-walkthrough.nix # solem-demo CLI
  ];

  # Abilita desktop grafico + auto-login per demo
  solem.desktop.enable = true;
  solem.desktop.autoLogin = true;
  solem.plymouth.enable = true;
  solem.defaultApps.enable = true;
  solem.defaultApps.profile = "minimal";  # solo essenziali (no developer/full)

  # Identità VM
  networking.hostName = "solem-desktop-demo";
  system.stateVersion = "24.11";
  networking.networkmanager.enable = true;

  # Boot/filesystem: gestiti da hardware-vm.nix

  # Tool base
  environment.systemPackages = with pkgs; [
    git curl vim htop
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  i18n.supportedLocales = [
    "it_IT.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  console.keyMap = "it";
}
