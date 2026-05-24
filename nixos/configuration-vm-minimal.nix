{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — solem-core + step 1-12 (verde) + 13a (safe).
# Step 14+ rimossi: tutti rossi anche dopo aver tolto step 13.
# Significa che il colpevole è in step 14+.

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
    # Step 4: shell + italian-locale + clipboard
    ./modules/solem-shell.nix
    ./modules/solem-italian-locale.nix
    ./modules/solem-clipboard.nix
    # Step 5: update + cli-extra + init + sysmon
    ./modules/solem-update.nix
    ./modules/solem-cli-extra.nix
    ./modules/solem-init.nix
    ./modules/solem-system-monitor.nix
    # Step 6: snapshots + recovery
    ./modules/solem-snapshots.nix
    ./modules/solem-recovery.nix
    # Step 7: secrets + power + services-hub
    ./modules/solem-secrets.nix
    ./modules/solem-power.nix
    ./modules/solem-power-profiles.nix
    ./modules/solem-services-hub.nix
    # Step 8: network tools + headscale + screen-tools
    ./modules/solem-network-tools.nix
    ./modules/solem-headscale.nix
    ./modules/solem-screen-tools.nix
    # Step 9: networking + security + boot
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
    # Step 10: 19 moduli "vita reale"
    ./modules/solem-bluetooth-audio.nix
    ./modules/solem-audio-bluetooth.nix
    ./modules/solem-print-scan.nix
    ./modules/solem-password-manager.nix
    ./modules/solem-pdf-tools.nix
    ./modules/solem-notifications.nix
    ./modules/solem-notes.nix
    ./modules/solem-finance.nix
    ./modules/solem-jupyter.nix
    ./modules/solem-database.nix
    ./modules/solem-photo-music.nix
    ./modules/solem-reading.nix
    ./modules/solem-smart-home.nix
    ./modules/solem-radicale.nix
    ./modules/solem-selfhost.nix
    ./modules/solem-mail-server.nix
    ./modules/solem-hpc.nix
    ./modules/solem-datacenter.nix
    ./modules/solem-spid-italia.nix
    # Step 11: 7 moduli safe
    ./modules/solem-accessibility.nix
    ./modules/solem-auditd.nix
    ./modules/solem-autoheal.nix
    ./modules/solem-backup-restic.nix
    ./modules/solem-battery-health.nix
    ./modules/solem-browser-hardened.nix
    ./modules/solem-cluster.nix
    # Step 12: 12 moduli vari
    ./modules/solem-communication.nix
    ./modules/solem-containers.nix
    ./modules/solem-crash-reporter.nix
    ./modules/solem-display.nix
    ./modules/solem-edge.nix
    ./modules/solem-email.nix
    ./modules/solem-greeter.nix
    ./modules/solem-handheld.nix
    ./modules/solem-hotspot.nix
    ./modules/solem-mobile.nix
    ./modules/solem-monitoring.nix
    ./modules/solem-overlay.nix
    # Step 13a/13b RIMOSSI per ripristinare baseline verde step 1-12 (88 moduli)
    # Vedi commit ca7efee verde confermato.
    # Quando 791b3bf / 573c0b0 conferma verde, riaggiungo 1 alla volta.
  ];

  # solem-memory: niente protezione gavio (non importato)
  solem.memory.protectGavio = false;

  # Abilita servizi essenziali
  solem.shell.enable = true;
  solem.italianLocale.enable = true;
  solem.clipboard.enable = true;
  solem.channel.enable = true;

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
