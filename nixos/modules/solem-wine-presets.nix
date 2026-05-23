{ config, pkgs, lib, ... }:

# SOLEM WINE PRESETS — preset per app Windows OPEN-SOURCE/FREEWARE.
#
# Single responsibility: SOLO installazione Wine + Bottles + helper
# `solem-wine` per le app Windows FOSS più richieste.
#
# Filosofia FOSS-only: SOLEM NON pre-configura prefix per software
# proprietario o a pagamento (Office, Photoshop, AutoCAD ecc.).
# L'utente che ne possiede licenza legale può creare prefix manualmente
# con `wineboot --init && winetricks <deps>`.
#
# Preset inclusi: solo software con licenza FOSS o freeware-libero.
# Costo: 0 €.

let
  cfg = config.solem.winePresets;

  # Preset solo FOSS / freeware noti
  presetsConfig = pkgs.writeText "wine-presets.json" (builtins.toJSON {
    "notepad-plus-plus" = {
      name = "Notepad++";
      license = "GPL-3.0";
      winetricks = [ ];
      arch = "win64";
      note = "Editor di testo GPL. Considera VSCodium nativo Linux.";
    };
    "directx-runtime" = {
      name = "DirectX Runtime (per giochi)";
      license = "Microsoft EULA (redistribuibile gratuito)";
      winetricks = [ "directx9" "vcrun2019" "d3dcompiler_47" "d3dx9" ];
      arch = "win64";
      note = "Base per giochi DX9-11. Usa DXVK per DX10/11.";
    };
    "msvc-runtimes-pack" = {
      name = "Microsoft Visual C++ Runtimes (redistribuibile)";
      license = "Microsoft EULA (free redistributable)";
      winetricks = [ "vcrun2005" "vcrun2008" "vcrun2010" "vcrun2013" "vcrun2015" "vcrun2017" "vcrun2019" ];
      arch = "win64";
      note = "Runtime gratuito redistribuibile (per app legacy che lo richiedono).";
    };
    "dotnet-pack" = {
      name = "Microsoft .NET Framework (redistribuibile)";
      license = "Microsoft EULA (free redistributable)";
      winetricks = [ "dotnet472" "dotnet48" ];
      arch = "win64";
      note = "Runtime .NET gratuito per app FOSS .NET.";
    };
    "vlc-windows" = {
      name = "VLC Media Player (per testare Windows build)";
      license = "GPL-2.0";
      winetricks = [ ];
      arch = "win64";
      note = "VLC è FOSS. Su SOLEM hai già VLC nativo. Questo preset serve solo se devi testare il build Windows.";
    };
    "audacity-windows" = {
      name = "Audacity (Windows build)";
      license = "GPL-2.0";
      winetricks = [ ];
      arch = "win64";
      note = "Audacity FOSS. Preferisci nativo Linux.";
    };
    "blender-windows" = {
      name = "Blender (Windows build)";
      license = "GPL-3.0";
      winetricks = [ ];
      arch = "win64";
      note = "Blender FOSS. Preferisci nativo Linux.";
    };
  });

  wineHelper = pkgs.writeShellApplication {
    name = "solem-wine";
    runtimeInputs = with pkgs; [ wineWowPackages.stable winetricks jq coreutils ];
    text = ''
      PRESETS="/etc/solem/wine-presets.json"
      ACTION="''${1:-list}"

      case "$ACTION" in
        list|ls)
          echo "  SOLEM Wine Presets — solo FOSS / freeware redistribuibile"
          echo
          jq -r 'to_entries[] | "  \(.key|.[0:24])  →  \(.value.name)  [\(.value.license)]"' "$PRESETS"
          echo
          echo "Per applicare un preset:  solem-wine apply <preset-id>"
          ;;
        info)
          [ -z "''${2:-}" ] && { echo "Usage: solem-wine info <preset-id>"; exit 1; }
          jq -r --arg p "$2" '.[$p] | "Name: \(.name)\nLicense: \(.license)\nArch: \(.arch)\nWinetricks: \(.winetricks | join(\", \"))\nNote: \(.note)"' "$PRESETS"
          ;;
        apply|init)
          [ -z "''${2:-}" ] && { echo "Usage: solem-wine apply <preset-id>"; exit 1; }
          PRESET="$2"
          ARCH=$(jq -r --arg p "$PRESET" '.[$p].arch // empty' "$PRESETS")
          if [ -z "$ARCH" ]; then
            echo "Preset $PRESET non trovato. Usa 'solem-wine list'."
            exit 1
          fi

          export WINEPREFIX="$HOME/.wine-$PRESET"
          export WINEARCH="$ARCH"
          mkdir -p "$WINEPREFIX"
          echo "Creating Wine prefix: $WINEPREFIX ($ARCH)"
          wineboot --init

          DEPS=$(jq -r --arg p "$PRESET" '.[$p].winetricks | join(" ")' "$PRESETS")
          if [ -n "$DEPS" ]; then
            echo "Installing winetricks deps: $DEPS"
            # shellcheck disable=SC2086
            winetricks -q $DEPS
          fi

          echo
          echo "✓ Preset $PRESET pronto in $WINEPREFIX"
          echo "  Per installer: WINEPREFIX=$WINEPREFIX wine /path/to/installer.exe"
          ;;
        bottles)
          echo "Lancio Bottles GUI (gestione visiva Wine prefix):"
          if command -v bottles >/dev/null 2>&1; then
            bottles &
            disown
          else
            echo "Bottles non installato. Installalo via:"
            echo "  solem-app install com.usebottles.bottles"
          fi
          ;;
        *)
          echo "solem-wine — runtime app Windows FOSS via Wine"
          echo
          echo "Comandi:"
          echo "  solem-wine list             → preset FOSS disponibili"
          echo "  solem-wine info <id>        → dettagli un preset"
          echo "  solem-wine apply <id>       → crea prefix + winetricks deps"
          echo "  solem-wine bottles          → lancia Bottles GUI"
          echo
          echo "Per software PROPRIETARIO (Office, Photoshop, AutoCAD, ecc.):"
          echo "  SOLEM NON pre-configura. Se hai la licenza, crea prefix"
          echo "  manualmente: WINEPREFIX=~/.wine-xxx wineboot --init"
          ;;
      esac
    '';
  };
in {
  options.solem.winePresets = {
    enable = lib.mkEnableOption "Wine + Bottles + preset app Windows FOSS (no proprietario)";

    installBottles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa Bottles GUI per gestione prefix";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wineWowPackages.stable
      winetricks
      wineHelper
    ] ++ lib.optional cfg.installBottles bottles;

    environment.etc."solem/wine-presets.json".source = presetsConfig;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
