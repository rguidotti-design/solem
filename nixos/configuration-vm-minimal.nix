{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — solem-core + tool basici.
# Ricostruzione incrementale: aggiungo 1-3 moduli per volta.
#
# IMPORTANTE: solem-core.nix dichiara già users.users.gavio + users.mutableUsers=false
# Non ridichiarare qui per evitare conflitti.

{
  imports = [
    ./modules/solem-core.nix
    # Step 1: CLI Python + banner + channel switcher
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    ./modules/solem-channels.nix
    # Step 2: watchdog + diagnostica (Python stdlib)
    ./modules/solem-keep.nix
    ./modules/solem-doctor.nix
    # Step 3: sicurezza base (sysctl + zram + sandbox)
    ./modules/solem-kernel-hardening.nix
    ./modules/solem-memory.nix
    ./modules/solem-sandbox.nix
    # Step 4: locale + shell TUI + clipboard
    ./modules/solem-italian-locale.nix
    ./modules/solem-shell.nix
    ./modules/solem-clipboard.nix
    # Step 5: update OTA + snapshots + CLI extra
    ./modules/solem-update.nix
    ./modules/solem-cli-extra.nix
    # Step 6: init script + system monitor tools (btop/bandwhich/dust/duf)
    ./modules/solem-init.nix
    ./modules/solem-system-monitor.nix
  ];

  # solem-memory: niente protezione gavio service (non importato nel minimal)
  solem.memory.protectGavio = false;

  # Abilita step 4
  solem.italianLocale.enable = true;
  solem.shell.enable = true;
  solem.clipboard.enable = true;

  # Identità
  networking.hostName = "solem-vm";
  system.stateVersion = "24.11";

  # Abilita channel switcher
  solem.channel.enable = true;

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
