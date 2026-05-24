{ config, pkgs, lib, ... }:

# SOLEM ISO OVERLAY — modificazioni per la live ISO.
#
# Single responsibility: SOLO le differenze rispetto a configuration-vm-minimal:
# - banner di benvenuto getty
# - Calamares installer pre-installato (se disponibile in nixpkgs)
# - branding navy/gold per Calamares

let
  welcomeBanner = ''
    ╔════════════════════════════════════════════════════╗
    ║          SOLEM — AI-native OS · live ISO           ║
    ║                                                    ║
    ║  user: gavio · pass: gavio                         ║
    ║                                                    ║
    ║  Installa con:                                     ║
    ║    sudo calamares                                  ║
    ║                                                    ║
    ║  Documentazione:                                   ║
    ║    https://github.com/rguidotti-design/solem       ║
    ╚════════════════════════════════════════════════════╝
  '';
in {
  # User live: utente "gavio" già dichiarato in solem-core con hashedPassword "gavio".
  # NON ridichiarare initialPassword/isSystemUser/isNormalUser → conflict.

  # ── Override CRITICI per ISO live ──
  # solem-core imposta `users.mutableUsers = false` per security.
  # L'installer ISO base (installation-cd-minimal.nix) ha bisogno di
  # mutableUsers=true e root passwordless. Forziamo override per ISO.
  users.mutableUsers = lib.mkForce true;
  users.users.root.hashedPassword = lib.mkForce null;
  users.users.root.initialHashedPassword = lib.mkForce "";

  # SSH su ISO live: passwordless root non deve essere esposto
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";

  # Network: NetworkManager su live
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = lib.mkForce true;
  services.getty.greetingLine = welcomeBanner;

  # === Calamares branding files (in /etc) ===
  # Branding files SOLEM in /etc/calamares — Calamares stesso aggiunto a
  # systemPackages solo se l'utente lo abilita esplicitamente
  # (alcune versioni 24.11 non hanno calamares-nixos).
  environment.etc."calamares/branding/solem/branding.desc" = {
    text = ''
      ---
      componentName: solem
      welcomeStyleCalamares: true
      strings:
          productName:         SOLEM
          shortProductName:    SOLEM
          version:             24.11-live
          shortVersion:        24.11
          versionedName:       SOLEM 24.11 live
          shortVersionedName:  SOLEM 24.11
          bootloaderEntryName: SOLEM
          productUrl:          https://github.com/rguidotti-design/solem
          supportUrl:          https://github.com/rguidotti-design/solem/issues
          releaseNotesUrl:     https://github.com/rguidotti-design/solem/releases
      style:
         sidebarBackground:    "#0B1426"
         sidebarText:          "#F5F5F5"
         sidebarTextSelect:    "#D4A24A"
         sidebarTextHighlight: "#D4A24A"
    '';
  };

  # Helper "solem-install" lancia Calamares
  environment.etc."solem/install.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      echo "── SOLEM Installer ──"
      echo "Calamares partirà tra 3 secondi..."
      sleep 3
      exec sudo -E calamares
    '';
  };

  # Firmware redistribuibile incluso (Wi-Fi/Intel/Realtek FOSS)
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # ISO settings
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  isoImage.isoName = lib.mkForce "solem-${config.system.nixos.release}-x86_64.iso";
  isoImage.volumeID = lib.mkForce "SOLEM_2411";
}
