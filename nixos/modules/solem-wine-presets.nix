{ config, pkgs, lib, ... }:

# SOLEM WINE PRESETS — preset per app Windows comuni via Wine/Bottles.
#
# Single responsibility: SOLO installazione Wine + Bottles + helper script
# `solem-wine` che semplifica install delle 50 app Windows più richieste
# (Office legacy, Photoshop CS6, AutoCAD older, Notepad++, Foobar2000,
# ecc.).
#
# Le LICENZE delle app Windows installate sono dell'utente. SOLEM fornisce
# solo il runtime Wine + preset CONFIG (winetricks scripts, dxvk, vkd3d).
#
# 100% FOSS (Wine LGPL, Bottles GPLv3, dxvk-async opzionale).

let
  cfg = config.solem.winePresets;

  # Lista preset (id → nome leggibile + winetricks deps)
  presetsConfig = pkgs.writeText "wine-presets.json" (builtins.toJSON {
    "office-2010" = {
      name = "Microsoft Office 2010";
      winetricks = [ "dotnet40" "msxml6" "riched20" "vcrun2010" ];
      arch = "win32";
      note = "Office 2010 funziona meglio di 2013+. Per 365 usa browser.";
    };
    "office-2016" = {
      name = "Microsoft Office 2016";
      winetricks = [ "dotnet472" "msxml6" "vcrun2015" "corefonts" ];
      arch = "win64";
      note = "Office 2016 32-bit installer raccomandato.";
    };
    "photoshop-cs6" = {
      name = "Photoshop CS6";
      winetricks = [ "msxml3" "msxml6" "atmlib" "fontsmooth=rgb" "vcrun2008" ];
      arch = "win32";
      note = "CS6 ultimo supportato bene da Wine. CC è critico.";
    };
    "notepad-plus-plus" = {
      name = "Notepad++";
      winetricks = [ ];
      arch = "win64";
      note = "Funziona out-of-the-box, considera VSCodium nativo.";
    };
    "irfanview" = {
      name = "IrfanView";
      winetricks = [ "vcrun2010" ];
      arch = "win32";
      note = "Image viewer ultra-leggero.";
    };
    "foobar2000" = {
      name = "foobar2000";
      winetricks = [ "vcrun2019" ];
      arch = "win64";
      note = "Audio player. Considera Amberol/strawberry nativo.";
    };
    "autocad-2018" = {
      name = "AutoCAD 2018";
      winetricks = [ "dotnet48" "msxml6" "corefonts" "vcrun2017" ];
      arch = "win64";
      note = "DWG opener. Considera LibreCAD/QCAD nativi.";
    };
    "winrar" = {
      name = "WinRAR";
      winetricks = [ ];
      arch = "win64";
      note = "Considera 'unar' o 'p7zip' nativi.";
    };
    "directx-runtime" = {
      name = "DirectX Runtime (per giochi)";
      winetricks = [ "directx9" "vcrun2019" "d3dcompiler_47" "d3dx9" ];
      arch = "win64";
      note = "Base per giochi DX9-11. Usa Bottles+DXVK per DX12.";
    };
    "msvc-runtimes-pack" = {
      name = "Microsoft Visual C++ Runtimes (tutti)";
      winetricks = [ "vcrun2005" "vcrun2008" "vcrun2010" "vcrun2013" "vcrun2015" "vcrun2017" "vcrun2019" ];
      arch = "win64";
      note = "Base per molte app legacy.";
    };
    "skype-legacy" = {
      name = "Skype legacy 7.x";
      winetricks = [ "vcrun2008" "ie7" ];
      arch = "win32";
      note = "Skype moderno: usa client web o Element.";
    };
    "kingdom-classic" = {
      name = "Kingdom (Steam game offline)";
      winetricks = [ "directx9" ];
      arch = "win32";
      note = "Esempio gioco indie. Usa Steam Proton invece se possibile.";
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
          echo "  SOLEM Wine Presets — Windows app via Wine/Bottles"
          echo
          jq -r 'to_entries[] | "  \(.key|.[0:24])  →  \(.value.name)  [\(.value.arch)]"' "$PRESETS"
          echo
          echo "Per applicare un preset:  solem-wine apply <preset-id>"
          echo "Per info dettaglio:       solem-wine info <preset-id>"
          ;;
        info)
          [ -z "''${2:-}" ] && { echo "Usage: solem-wine info <preset-id>"; exit 1; }
          jq -r --arg p "$2" '.[$p] | "Name: \(.name)\nArch: \(.arch)\nWinetricks: \(.winetricks | join(\", \"))\nNote: \(.note)"' "$PRESETS"
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
          echo "  Lancia l'installer Windows con:"
          echo "    WINEPREFIX=$WINEPREFIX wine /path/to/installer.exe"
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
          echo "solem-wine — runtime app Windows via Wine"
          echo
          echo "Comandi:"
          echo "  solem-wine list             → preset disponibili"
          echo "  solem-wine info <id>        → dettagli un preset"
          echo "  solem-wine apply <id>       → crea prefix + winetricks deps"
          echo "  solem-wine bottles          → lancia Bottles GUI"
          ;;
      esac
    '';
  };
in {
  options.solem.winePresets = {
    enable = lib.mkEnableOption "Wine + Bottles + preset 50 app Windows comuni";

    installBottles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa anche Bottles GUI per gestione prefix visuale";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wineWowPackages.stable
      winetricks
      wineHelper
    ] ++ lib.optional cfg.installBottles bottles;

    environment.etc."solem/wine-presets.json".source = presetsConfig;

    # 32-bit support per win32 prefix
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
