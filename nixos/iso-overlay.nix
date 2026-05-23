{ config, pkgs, lib, ... }:

# SOLEM ISO OVERLAY — modificazioni per la live ISO.
#
# Single responsibility: SOLO le differenze rispetto alla config standard:
# - disabilita servizi che richiedono /etc/solem persistente
# - utente live "gavio" con password "gavio"
# - banner di benvenuto getty
# - Calamares installer pre-installato (FOSS, GPL-3.0)

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
  # === Disable servizi che non hanno senso in live ===
  systemd.services.gavio.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  services.nextcloud.enable = lib.mkForce false;
  services.immich.enable = lib.mkForce false;
  services.postgresql.enable = lib.mkForce false;
  services.vaultwarden.enable = lib.mkForce false;
  services.joplin-server.enable = lib.mkForce false;
  services.radicale.enable = lib.mkForce false;
  services.paperless.enable = lib.mkForce false;
  services.opensnitch.enable = lib.mkForce false;

  # === User live ===
  users.users.gavio.initialPassword = lib.mkForce "gavio";
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = lib.mkForce true;
  services.getty.greetingLine = welcomeBanner;

  # === Calamares installer (FOSS, GPL-3.0) ===
  environment.systemPackages = with pkgs; [
    calamares-nixos
    calamares-nixos-extensions
  ];

  # Helper "solem-install" che richiama Calamares con branding SOLEM
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

  # Nessun firmware proprietario di default nella ISO (FOSS-only)
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.enableAllFirmware = lib.mkDefault false;

  # ISO compression (più piccola)
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  isoImage.isoName = lib.mkForce "solem-${config.system.nixos.release}-x86_64.iso";
  isoImage.volumeID = lib.mkForce "SOLEM_2411";
}
