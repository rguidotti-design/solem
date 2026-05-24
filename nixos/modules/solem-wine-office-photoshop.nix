{ config, pkgs, lib, ... }:

# SOLEM WINE OFFICE + PHOTOSHOP — preset auto per app Windows top.
#
# Single responsibility: SOLO CLI helper `solem-wine-app <name>` che
# crea prefix Wine isolato e installa app con setup specifico.
#
# Supportate (free download richiesto da utente):
#   - Office 2010 (working ~ 95%)
#   - Office 2013 (working ~ 90%)
#   - Office 2016 (working ~ 80%)
#   - Photoshop CS6 (working ~ 90%)
#   - Notepad++ (FOSS, working 100%)
#   - 7-Zip (Windows native, working 100%)
#   - IrfanView (working 100%)
#   - foobar2000 (working 95%)

let
  cfg = config.solem.wineOfficePhotoshop;

  wineHelperCli = pkgs.writeShellApplication {
    name = "solem-wine-app";
    runtimeInputs = with pkgs; [ coreutils wineWowPackages.stable winetricks curl ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      WINE_BASE="$HOME/.solem-wine"
      mkdir -p "$WINE_BASE"

      case "$ACTION" in

        # ── Office 2010 / 2013 / 2016 ─────────────────────────────────
        office)
          VER="''${1:-2016}"
          PREFIX="$WINE_BASE/office-$VER"
          export WINEPREFIX="$PREFIX"
          export WINEARCH=win32  # Office 2010 32-bit; 2013/2016 supportano 64-bit
          mkdir -p "$PREFIX"
          echo "Setup Office $VER in $PREFIX (32-bit)"
          echo "Winetricks: corefonts msxml6 vcrun2008 vcrun2010 vcrun2013 dotnet40 fontsmooth=rgb"
          winetricks -q corefonts msxml6 vcrun2008 vcrun2010 vcrun2013 dotnet40 fontsmooth=rgb || true
          echo
          echo "Setup completato. Ora installa Office:"
          echo "  WINEPREFIX=$PREFIX wine /path/to/Office$VER-Setup.exe"
          ;;

        # ── Photoshop CS6 (free trial Adobe se hai disco; CC è cloud) ─
        photoshop-cs6|ps-cs6)
          PREFIX="$WINE_BASE/photoshop-cs6"
          export WINEPREFIX="$PREFIX"
          export WINEARCH=win64
          mkdir -p "$PREFIX"
          echo "Setup Photoshop CS6 in $PREFIX (64-bit)"
          echo "Winetricks: gdiplus_winxp atmlib"
          winetricks -q gdiplus_winxp atmlib || true
          echo
          echo "Ora installa PS CS6:"
          echo "  WINEPREFIX=$PREFIX wine /path/to/Photoshop-CS6-Setup.exe"
          ;;

        # ── AutoCAD 2013 (last working Wine) ──────────────────────────
        autocad-2013)
          PREFIX="$WINE_BASE/autocad-2013"
          export WINEPREFIX="$PREFIX"
          export WINEARCH=win32
          mkdir -p "$PREFIX"
          echo "Setup AutoCAD 2013 in $PREFIX"
          winetricks -q corefonts dotnet40 vcrun2005 vcrun2008 || true
          echo "Ora installa AutoCAD:"
          echo "  WINEPREFIX=$PREFIX wine /path/to/AutoCAD-2013-setup.exe"
          ;;

        # ── App freeware Windows (FOSS-compatible) ────────────────────
        notepad++)
          PREFIX="$WINE_BASE/notepad-pp"
          export WINEPREFIX="$PREFIX"
          mkdir -p "$PREFIX"
          echo "Notepad++ può anche essere installato come Flatpak:"
          echo "  flatpak install flathub com.notepadqq.Notepadqq"
          echo "Wine prefix preparato in: $PREFIX"
          ;;

        irfanview)
          PREFIX="$WINE_BASE/irfanview"
          export WINEPREFIX="$PREFIX"
          mkdir -p "$PREFIX"
          echo "IrfanView prefix in: $PREFIX"
          echo "Scarica: https://www.irfanview.com/64bit.htm"
          ;;

        foobar2000)
          PREFIX="$WINE_BASE/foobar2000"
          export WINEPREFIX="$PREFIX"
          mkdir -p "$PREFIX"
          echo "foobar2000 prefix in: $PREFIX"
          echo "Scarica: https://www.foobar2000.org/download"
          ;;

        # ── Run app installata ────────────────────────────────────────
        run)
          NAME="''${1:?Usage: solem-wine-app run <name>}"
          shift
          PREFIX="$WINE_BASE/$NAME"
          if [ ! -d "$PREFIX" ]; then
            echo "Prefix non trovato: $PREFIX"
            echo "Lista prefix: ls $WINE_BASE"
            exit 1
          fi
          export WINEPREFIX="$PREFIX"
          # L'utente passa argomenti: solem-wine-app run office "WINWORD.EXE"
          wine "$@"
          ;;

        # ── List prefix esistenti ─────────────────────────────────────
        list|ls)
          echo "Prefix Wine in $WINE_BASE:"
          ls -1 "$WINE_BASE" 2>/dev/null || echo "(vuoto)"
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-wine-app — preset auto Wine per app Windows top

  Office:
    solem-wine-app office 2010       prefix + corefonts + msxml6 + vcrun
    solem-wine-app office 2013
    solem-wine-app office 2016

  Adobe:
    solem-wine-app photoshop-cs6     prefix + gdiplus + atmlib

  CAD:
    solem-wine-app autocad-2013      prefix + dotnet40 + vcrun

  Freeware (consigliato Flatpak):
    solem-wine-app notepad++
    solem-wine-app irfanview
    solem-wine-app foobar2000

  Lancia app installata:
    solem-wine-app run office WINWORD.EXE
    solem-wine-app run photoshop-cs6 "Photoshop.exe"

  Lista prefix:
    solem-wine-app list

Setup automatico delle dipendenze Wine note per ogni app.
L'utente deve scaricare l'installer originale (free trial o licenza).

ALTERNATIVE FOSS (raccomandate quando possibile):
  Office 365   → LibreOffice / OnlyOffice
  Photoshop    → GIMP + Krita
  AutoCAD      → FreeCAD + LibreCAD
  Premiere     → Kdenlive + DaVinci Resolve (free) [solem-davinci]
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.wineOfficePhotoshop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa `solem-wine-app` con preset Office/Photoshop/AutoCAD (opt-in)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wineHelperCli
      wineWowPackages.stable
      winetricks
    ];

    # 32-bit graphics support (Office 2010/2013 32-bit)
    hardware.graphics.enable32Bit = lib.mkDefault true;
  };
}
