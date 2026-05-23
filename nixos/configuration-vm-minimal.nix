{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — usata dalla CI per build veloce e affidabile.
#
# Single responsibility: SOLO i moduli core che sappiamo compilare in
# nixpkgs 24.11 senza pacchetti rischiosi. Niente Bruno / SimpleX /
# Cinny / Albert / Pika / Immich / Nextcloud (richiedono opzioni
# servizio che possono variare tra release).
#
# Per il sistema "completo" usa configuration.nix (per Beelink/Workstation).
# Questo file è solo per smoke test CI + nix build .#vm rapido.

{
  imports = [
    # Core obbligatorio
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    ./modules/solem-channels.nix
    ./modules/solem-keep.nix
    ./modules/solem-doctor.nix

    # Sicurezza base (default-on)
    ./modules/solem-kernel-hardening.nix
    ./modules/solem-memory.nix
    ./modules/solem-sandbox.nix

    # Italian locale (FOSS-solid)
    ./modules/solem-italian-locale.nix
  ];

  # Identità
  networking.hostName = "solem-vm";
  networking.domain = "local";
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  # Locale Italia (anche se solem-italian-locale lo gestisce, qui sovrascriviamo
  # con mkForce per essere sicuri)
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = lib.mkForce "it_IT.UTF-8";
  console.keyMap = "it";
  solem.italianLocale.enable = true;

  # Utente default
  users.users.gavio = {
    isNormalUser = true;
    initialPassword = "gavio";
    extraGroups = [ "wheel" "networkmanager" ];
  };
  users.mutableUsers = true;

  # Network base (DHCP)
  networking.networkmanager.enable = true;

  # Tool base sempre presenti
  environment.systemPackages = with pkgs; [
    git curl wget vim neovim
    htop btop tmux jq yq
    ripgrep fd bat eza tree
    python312 uv
    openssl gnupg
    unzip zip
  ];

  # Minimal SSH per debug VM via console
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };
}
