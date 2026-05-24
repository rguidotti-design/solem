{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — ULTRA-MINIMAL per debug CI.
# Solo solem-core (step 0).

{
  imports = [
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    ./modules/solem-public-apis.nix
    ./modules/solem-demo.nix    # riaggiunto: gum rimosso, solo echo
    ./modules/solem-quick-search.nix  # fd + rg + fzf
    ./modules/solem-clipboard-share.nix  # solem-clip HTTP share
    ./modules/solem-productivity.nix     # solem-pomo + solem-todo + solem-note
    ./modules/solem-smart-install.nix    # solem-app store unificato
    ./modules/solem-migrate-windows.nix  # migrazione NTFS Windows
    ./modules/solem-snap-layouts.nix     # Hyprland binds Win-style
    ./modules/solem-hw-just-works.nix    # sane defaults HW (opt-in default false)
    ./modules/solem-davinci.nix          # DaVinci Resolve helper
    ./modules/solem-wine-office-photoshop.nix  # Office/Photoshop wine preset
    ./modules/solem-steam-deck.nix       # gaming Steam Deck-like
    ./modules/solem-dictation-live.nix   # speech-to-text whisper.cpp
    ./modules/solem-cloud-auto-pair.nix  # solem-cloud QR pair Nextcloud
    ./modules/solem-ai-shortcuts.nix     # Super+T/M/W/D/R/G quick AI actions
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
