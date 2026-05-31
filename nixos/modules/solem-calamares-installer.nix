{ config, pkgs, lib, ... }:

# SOLEM CALAMARES INSTALLER — Step 31: GUI installer + branding completo.
#
# Single responsibility: SOLO Calamares installer + branding SOLEM
# (logo, colori, modules list). Estende l'iso-overlay.nix che ha gia'
# il file branding parziale.
#
# Workflow user (post-step 31):
#   1. Boot ISO live (build .#iso = pronta da CI)
#   2. Login auto: user "gavio", pw "gavio"
#   3. Doppio-click icona "Install SOLEM" (Calamares)
#   4. Wizard step-by-step: keyboard, partition, user, locale
#   5. Install in 5-15min → reboot → SOLEM installato
#
# Tutto FOSS (Calamares GPL-3.0). 0 €.

let
  cfg = config.solem.calamaresInstaller;
in {
  options.solem.calamaresInstaller = {
    enable = lib.mkEnableOption "Calamares installer GUI (per ISO live)";

    productName = lib.mkOption {
      type = lib.types.str;
      default = "SOLEM";
      description = "Nome prodotto mostrato in wizard";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "24.11";
      description = "Version string";
    };

    welcomeUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/rguidotti-design/solem";
      description = "URL home page mostrata nel welcome screen";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pacchetti: Calamares + nixos extensions
    environment.systemPackages = with pkgs; [
      calamares-nixos
      calamares-nixos-extensions
      (pkgs.writeShellApplication {
        name = "solem-install";
        runtimeInputs = with pkgs; [ coreutils calamares-nixos ];
        text = ''
          # Wrapper user-friendly per launcher Calamares
          echo "╔══════════════════════════════════════════════════╗"
          echo "║       SOLEM Installer — Calamares GUI            ║"
          echo "║       AI-native OS                               ║"
          echo "╚══════════════════════════════════════════════════╝"
          echo
          echo "Avvio installer in 3 secondi..."
          sleep 3
          exec sudo -E calamares
        '';
      })
    ];

    # Desktop file per icona "Install SOLEM" su desktop live
    environment.etc."xdg/autostart/solem-install-welcome.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Installa SOLEM
      Comment=Installa SOLEM sul disco con Calamares
      Exec=solem-install
      Icon=system-software-install
      Categories=System;
      Terminal=true
    '';

    # Branding Calamares: extends iso-overlay branding.desc esistente
    environment.etc."calamares/branding/solem/branding.desc" = lib.mkForce {
      text = ''
        ---
        componentName: solem
        welcomeStyleCalamares: true
        welcomeExpandingLogo: true

        strings:
            productName:         ${cfg.productName}
            shortProductName:    ${cfg.productName}
            version:             ${cfg.version}
            shortVersion:        ${cfg.version}
            versionedName:       ${cfg.productName} ${cfg.version}
            shortVersionedName:  ${cfg.productName} ${cfg.version}
            bootloaderEntryName: ${cfg.productName}
            productUrl:          ${cfg.welcomeUrl}
            supportUrl:          ${cfg.welcomeUrl}/issues
            releaseNotesUrl:     ${cfg.welcomeUrl}/releases

        images:
            productLogo:         logo.png
            productIcon:         logo.png
            productWelcome:      welcome.png

        slideshow:               show.qml
        slideshowAPI:            2

        style:
           sidebarBackground:    "#0B1426"
           sidebarText:          "#F5F5F5"
           sidebarTextSelect:    "#D4A24A"
           sidebarTextHighlight: "#D4A24A"
           sidebarBackgroundSelected: "#1A2540"
      '';
    };

    # Logo placeholder (utente puo' sostituire post-install)
    environment.etc."calamares/branding/solem/logo.png" = lib.mkIf
      (builtins.pathExists ../assets/solem-logo.png)
      { source = ../assets/solem-logo.png; };

    # Slideshow QML
    environment.etc."calamares/branding/solem/show.qml".text = ''
      import QtQuick 2.5
      import calamares.slideshow 1.0

      Presentation {
          id: presentation

          Timer {
              interval: 5000
              running: true
              repeat: true
              onTriggered: presentation.goToNextSlide()
          }

          Slide {
              centeredText: "SOLEM — AI-native OS\nSicurezza zero-trust, FOSS, 0 €."
          }
          Slide {
              centeredText: "27 layer di sicurezza\nIncluso auto-attack notturno + self-heal"
          }
          Slide {
              centeredText: "GAVIO — la tua AI personale\nIntegrata e isolata in SOLEM"
          }
          Slide {
              centeredText: "Installazione in 5-15 minuti.\nReboot e sei pronto."
          }
      }
    '';

    # Settings Calamares per NixOS
    environment.etc."calamares/settings.conf".text = ''
      ---
      modules-search: [ local, /run/current-system/sw/lib/calamares/modules ]

      instances:
      - id:       rootfs
        module:   unpackfs
        config:   unpackfs.conf

      sequence:
      - show:
        - welcome
        - locale
        - keyboard
        - partition
        - users
        - summary

      - exec:
        - partition
        - mount
        - unpackfs
        - machineid
        - fstab
        - locale
        - keyboard
        - localecfg
        - users
        - displaymanager
        - networkcfg
        - hwclock
        - services-systemd
        - bootloader-config
        - grubcfg
        - bootloader
        - umount

      - show:
        - finished

      branding: solem

      prompt-install: true
      dont-chroot: false
    '';

    # Welcome screen config: messaggio benvenuto
    environment.etc."calamares/modules/welcome.conf".text = ''
      ---
      showSupportUrl:         true
      showKnownIssuesUrl:     false
      showReleaseNotesUrl:    true
      requirements:
        requiredStorage:     8.0
        requiredRam:         2.0
        internetCheckUrl:    https://cache.nixos.org
        check:
          - storage
          - ram
          - power
          - internet
          - root
          - screen
        required:
          - storage
          - ram
          - root
    '';
  };
}
