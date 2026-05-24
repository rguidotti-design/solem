{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — solem-core + tool basici.
# Ricostruzione incrementale: aggiungo 1 modulo per volta.
#
# IMPORTANTE: solem-core.nix dichiara già users.users.gavio + users.mutableUsers=false
# Non ridichiarare qui per evitare conflitti.
#
# BINARY SEARCH STEP 4: ultimo commit verde = c41fde7 (step 3).
# Step 4 ha aggiunto italian-locale + shell + clipboard insieme → rotto.
# Aggiungo SOLO shell per ora (Python stdlib, più sicuro).

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
    # Step 4a: solo shell TUI (binary search)
    ./modules/solem-shell.nix
    # Step 4b: italian-locale (font dubbi rimossi in ad95572)
    ./modules/solem-italian-locale.nix
    # Step 4c: clipboard (cliphist + wl-clipboard + xclip)
    ./modules/solem-clipboard.nix
    # Step 5: update OTA opt-in + CLI extra + init + system monitor
    ./modules/solem-update.nix
    ./modules/solem-cli-extra.nix
    ./modules/solem-init.nix
    ./modules/solem-system-monitor.nix
    # Step 6: snapshots + recovery (opt-in)
    ./modules/solem-snapshots.nix
    ./modules/solem-recovery.nix
    # Step 7: secrets + power + services-hub (tutti opt-in default off)
    ./modules/solem-secrets.nix
    ./modules/solem-power.nix
    ./modules/solem-power-profiles.nix
    ./modules/solem-services-hub.nix
    # Step 8: network tools + headscale + screen-tools (opt-in)
    ./modules/solem-network-tools.nix
    ./modules/solem-headscale.nix
    ./modules/solem-screen-tools.nix
    # Step 9: networking + security + boot (10 moduli, tutti opt-in default off)
    ./modules/solem-dns-private.nix
    ./modules/solem-dns-blocker.nix
    ./modules/solem-tor.nix
    ./modules/solem-wake-on-lan.nix
    ./modules/solem-tpm.nix
    ./modules/solem-usbguard.nix
    ./modules/solem-secure-boot.nix
    ./modules/solem-mesh.nix
    ./modules/solem-zero-trust.nix
    ./modules/solem-double-vpn.nix
  ];

  # solem-memory: niente protezione gavio service (non importato nel minimal)
  solem.memory.protectGavio = false;

  # Abilita shell + italian + clipboard
  solem.shell.enable = true;
  solem.italianLocale.enable = true;
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
