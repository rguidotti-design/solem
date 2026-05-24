{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — solo solem-core per ora.
# Ricostruzione incrementale: aggiungo 1 modulo per volta dopo CI verde.

{
  imports = [
    ./modules/solem-core.nix
  ];

  # Identità
  networking.hostName = "solem-vm";
  system.stateVersion = "24.11";

  # Utente di test
  users.users.gavio = {
    isNormalUser = true;
    initialPassword = "gavio";
    extraGroups = [ "wheel" "networkmanager" ];
  };
  users.mutableUsers = true;

  # Network base
  networking.networkmanager.enable = true;

  # Tool base
  environment.systemPackages = with pkgs; [
    git curl vim
    htop
    python312
  ];

  # SSH per debug VM
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  # Locale + timezone Italia
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  i18n.supportedLocales = [
    "it_IT.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  console.keyMap = "it";
}
