{ config, pkgs, lib, ... }:

# SOLEM INSTALLER GRAPHICAL — Calamares GUI + branding + skin SOLEM.
#
# Single responsibility: SOLO configurare Calamares per installazione
# grafica "1-click" da ISO live. Risponde WEAKNESSES.md GRAVE #2
# "Onboarding zero-knowledge".
#
# Differente da iso-overlay.nix: questo modulo può essere importato anche
# nel sistema installato (utile per "reinstall from running system").
# iso-overlay = solo per la ISO live.

let
  cfg = config.solem.installerGraphical;

  brandingDesc = pkgs.writeText "solem-branding.desc" ''
    ---
    componentName: solem
    welcomeStyleCalamares: true
    welcomeExpandingLogo: true

    strings:
        productName:         SOLEM
        shortProductName:    SOLEM
        version:             24.11
        shortVersion:        24.11
        versionedName:       SOLEM 24.11
        shortVersionedName:  SOLEM 24.11
        bootloaderEntryName: SOLEM
        productUrl:          https://github.com/rguidotti-design/solem
        supportUrl:          https://github.com/rguidotti-design/solem/issues
        releaseNotesUrl:     https://github.com/rguidotti-design/solem/releases

    images:
        productLogo:         "logo.png"
        productIcon:         "icon.png"
        productWelcome:      "welcome.png"

    slideshow:               "show.qml"

    style:
        sidebarBackground:    "#0B1426"
        sidebarText:          "#F5F5F5"
        sidebarTextSelect:    "#D4A24A"
        sidebarTextHighlight: "#D4A24A"
  '';

  # Slide-show QML (mostrato durante install per intrattenere)
  slideshowQml = pkgs.writeText "show.qml" ''
    import QtQuick 2.5
    import calamares.slideshow 1.0

    Presentation {
      id: presentation

      function nextSlide() {
        console.log("QML Component (default slideshow) Next slide");
        presentation.goToNextSlide();
      }

      Timer { interval: 30000; running: true; repeat: true; onTriggered: nextSlide() }

      Slide {
        Image { id: img1; source: "slide1.png"; width: parent.width * 0.7; anchors.centerIn: parent; fillMode: Image.PreserveAspectFit }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
               text: "SOLEM — OS AI-native · 100% FOSS · 0 € per sempre"; color: "#D4A24A"; font.family: "Inter" }
      }
      Slide {
        Text { anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; color: "#F5F5F5"; font.family: "Inter"
               text: "GAVIO — la tua AI personale\n\nLocal-first · No cloud · No tracking" }
      }
      Slide {
        Text { anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; color: "#F5F5F5"; font.family: "Inter"
               text: "Multi-device\n\nworkstation + laptop + smartphone + glass\nstesso account, federation Ed25519" }
      }
      Slide {
        Text { anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; color: "#F5F5F5"; font.family: "Inter"
               text: "Privacy by default\n\nZero telemetria · sandbox app · GPG/2FA preinstalled\nWipe sicuro · Tor opt-in" }
      }
    }
  '';

  # Settings.conf — modules da girare durante install
  settingsConf = pkgs.writeText "settings.conf" ''
    ---
    modules-search: [ local, /run/current-system/sw/lib/calamares/modules ]

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

  # Launcher
  installerLauncher = pkgs.writeShellApplication {
    name = "solem-installer";
    runtimeInputs = with pkgs; [ calamares-nixos coreutils ];
    text = ''
      if [ "$EUID" -ne 0 ]; then
        echo "Richiede root. Eseguo con sudo..."
        exec sudo -E "$0" "$@"
      fi
      echo "── SOLEM Installer ──"
      echo "Branding SOLEM (navy + gold) + slide-show 4 schermate"
      echo "Avvio Calamares in 3 secondi..."
      sleep 3
      exec calamares -d
    '';
  };
in {
  options.solem.installerGraphical = {
    enable = lib.mkEnableOption "Calamares installer grafico con branding SOLEM";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Lancia automaticamente l'installer all'avvio della ISO live.
        Default off (l'utente sceglie esplicitamente con `solem-installer`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      installerLauncher
      calamares-nixos
      calamares-nixos-extensions
    ];

    # File branding + settings in /etc/calamares
    environment.etc."calamares/branding/solem/branding.desc".source = brandingDesc;
    environment.etc."calamares/branding/solem/show.qml".source = slideshowQml;
    environment.etc."calamares/settings.conf".source = settingsConf;

    # Auto-start installer al primo boot ISO (se enabled)
    systemd.services.solem-installer-autostart = lib.mkIf cfg.autoStart {
      description = "SOLEM auto-launch Calamares on live ISO";
      wantedBy = [ "graphical.target" ];
      after = [ "graphical.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${installerLauncher}/bin/solem-installer";
        Restart = "no";
      };
    };
  };
}
