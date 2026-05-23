{ config, pkgs, lib, ... }:

# SOLEM ISO OVERLAY — modificazioni per la live ISO.
#
# Single responsibility: SOLO le differenze rispetto a configuration-vm-minimal:
# - utente live "gavio" con password "gavio"
# - banner di benvenuto getty
# - Calamares installer pre-installato (FOSS, GPL-3.0)
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
  # === User live ===
  users.users.gavio.initialPassword = lib.mkForce "gavio";
  users.users.gavio.isSystemUser = lib.mkForce false;
  users.users.gavio.isNormalUser = lib.mkForce true;

  # Network: NetworkManager su live
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = lib.mkForce true;
  services.getty.greetingLine = welcomeBanner;

  # === Calamares installer (FOSS, GPL-3.0) ===
  environment.systemPackages = with pkgs; [
    calamares-nixos
    calamares-nixos-extensions
  ];

  # === Branding SOLEM per Calamares (navy + gold) ===
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
  hardware.enableAllFirmware = lib.mkDefault false;

  # ISO settings
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  isoImage.isoName = lib.mkForce "solem-${config.system.nixos.release}-x86_64.iso";
  isoImage.volumeID = lib.mkForce "SOLEM_2411";
}
