{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — ULTRA-MINIMAL per debug CI.
# Solo solem-core (step 0).

{
  imports = [
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    # ./modules/solem-demo.nix  # TEMP rimosso: verificare se rompe Quick Validate
  ];

  # Identità
  networking.hostName = "solem-vm";
  system.stateVersion = "24.11";
  networking.networkmanager.enable = true;

  # Tool base
  environment.systemPackages = with pkgs; [
    git curl vim
    htop
    python312
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
