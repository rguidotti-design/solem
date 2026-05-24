{ config, pkgs, lib, ... }:

# SOLEM APP COMPAT — runtime per ESEGUIRE app di qualsiasi OS.
#
# Single responsibility: SOLO orchestrare i compatibility layer FOSS:
# - Flatpak    → app Linux moderne (Flathub repo)
# - AppImage   → app Linux portable (libfuse + appimage-run)
# - Distrobox  → container con qualsiasi distro Linux (Ubuntu/Fedora/Arch/...)
# - Wine + Winetricks + Bottles → app Windows (Office, Photoshop con limiti)
# - Waydroid   → app Android su Wayland (FOSS only)
# - Snap (opt-in) → snap store
#
# Risponde a "1) fai in modo che le app esistenti tu le possa installare"
# di WEAKNESSES.md sezione 🔴 GRAVI #3 "App ecosystem reale".
#
# Tutti i layer sono FOSS, 0 €. Le SINGOLE app che gli utenti installano
# possono essere closed-source — è loro scelta esplicita (es. "voglio
# Photoshop via Wine" è dell'utente, SOLEM solo abilita il runtime).

let
  cfg = config.solem.appCompat;

  # CLI universale "solem-install <type> <name>"
  installCli = pkgs.writeShellApplication {
    name = "solem-install";
    runtimeInputs = with pkgs; [ flatpak appimage-run distrobox wine coreutils ];
    text = ''
      ACTION="''${1:-help}"
      shift || true
      case "$ACTION" in
        flatpak|flat)
          ID="''${1:?Usage: solem-install flatpak <flatpak-id>}"
          echo "→ Flatpak install $ID (da Flathub)"
          flatpak install -y flathub "$ID"
          ;;
        appimage|appim)
          PATH_AI="''${1:?Usage: solem-install appimage <path/to/file.AppImage>}"
          chmod +x "$PATH_AI"
          echo "→ Esegui: appimage-run $PATH_AI"
          appimage-run "$PATH_AI"
          ;;
        windows|win|wine)
          EXE="''${1:?Usage: solem-install windows <installer.exe>}"
          PREFIX="''${WINEPREFIX:-$HOME/.wine-solem}"
          export WINEPREFIX="$PREFIX"
          echo "→ Wine prefix: $PREFIX"
          wine "$EXE"
          ;;
        android|apk)
          APK="''${1:?Usage: solem-install android <file.apk>}"
          if command -v waydroid >/dev/null 2>&1; then
            waydroid app install "$APK"
          else
            echo "Waydroid non attivo. Abilita con solem.appCompat.waydroid = true"
          fi
          ;;
        distro|distrobox)
          DISTRO="''${1:?Usage: solem-install distro <ubuntu|fedora|arch|debian>}"
          NAME="solem-$DISTRO"
          case "$DISTRO" in
            ubuntu)  IMG="quay.io/toolbx-images/ubuntu-toolbox:22.04" ;;
            fedora)  IMG="registry.fedoraproject.org/fedora-toolbox:latest" ;;
            arch)    IMG="quay.io/toolbx-images/archlinux-toolbox:latest" ;;
            debian)  IMG="quay.io/toolbx-images/debian-toolbox:12" ;;
            *) echo "Distro non supportata: $DISTRO"; exit 1 ;;
          esac
          distrobox create --name "$NAME" --image "$IMG" --yes
          echo "→ Entra con: distrobox enter $NAME"
          ;;
        bottle|bottles)
          echo "→ Apro Bottles (GUI per Wine prefix isolati)"
          bottles &
          ;;
        list)
          echo "── App installate ──"
          echo
          echo "[Flatpak]"
          flatpak list --app --columns=name,application 2>/dev/null | head -20
          echo
          echo "[Distrobox]"
          distrobox list 2>/dev/null || echo "(nessun container)"
          echo
          echo "[Wine prefix]"
          ls -1d "$HOME"/.wine* 2>/dev/null || echo "(nessun prefix)"
          ;;
        *)
          cat <<'HELP'
solem-install — installa app di qualsiasi OS su SOLEM

  Linux app moderne (raccomandato):
    solem-install flatpak <id>           Flathub (es. org.mozilla.firefox)
    solem-install appimage <file.AppImage>

  Windows app via Wine:
    solem-install windows <installer.exe>
    solem-install bottles                GUI gestore prefix Wine

  Android app:
    solem-install android <file.apk>     (richiede Waydroid attivo)

  Distro Linux qualsiasi (in container):
    solem-install distro ubuntu          Ubuntu 22.04
    solem-install distro fedora          Fedora latest
    solem-install distro arch            Arch Linux
    solem-install distro debian          Debian 12

  Inventario:
    solem-install list                   lista tutto l'installato
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.appCompat = {
    enable = lib.mkEnableOption "Runtime compatibility per app Linux/Windows/Android/multi-distro";

    flatpak = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Flatpak + Flathub repo (raccomandato; default Linux app store moderno)";
    };

    appimage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "AppImage runtime (libfuse + appimage-run)";
    };

    distrobox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Distrobox + Podman per container Ubuntu/Fedora/Arch/Debian";
    };

    wine = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Wine + Winetricks + Bottles per app Windows (Office, Photoshop con limiti)";
    };

    waydroid = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Waydroid — Android app su Wayland (opt-in, ~ 2 GB)";
    };
    # Snap NON incluso: in NixOS richiede nix-snapd flake esterno e ha
    # interazioni problematiche col Nix store. Gli utenti che vogliono
    # snap usino l'overlay nix-snapd manualmente.
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; lib.flatten [
        [ installCli ]

        # AppImage runtime
        (lib.optionals cfg.appimage [
          appimage-run
        ])

        # Distrobox + Podman per container
        (lib.optionals cfg.distrobox [
          distrobox
          podman
          podman-compose
        ])

        # Wine completo + GUI
        (lib.optionals cfg.wine [
          wineWowPackages.stable    # 64+32 bit (Office richiede 32)
          winetricks
          bottles                   # GUI gestione prefix
          mono                      # .NET Framework Wine
          dxvk                      # DirectX 11 → Vulkan
        ])
      ];
    }

    # Flatpak (richiede systemd activation + xdg-portal)
    (lib.mkIf cfg.flatpak {
      services.flatpak.enable = true;

      # Aggiungi Flathub al primo boot (idempotente)
      systemd.services.solem-flathub-setup = {
        description = "SOLEM: aggiungi Flathub al primo boot";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.flatpak ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          flatpak remote-add --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo || true
        '';
      };

      # Portal per Flatpak permissions runtime
      xdg.portal = {
        enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
      };
    })

    # Distrobox/Podman: virtualisation
    (lib.mkIf cfg.distrobox {
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
      virtualisation.containers.enable = true;
    })

    # 32-bit graphics support per Wine
    (lib.mkIf cfg.wine {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
    })

    # Waydroid
    (lib.mkIf cfg.waydroid {
      virtualisation.waydroid.enable = true;
    })
  ]);
}
