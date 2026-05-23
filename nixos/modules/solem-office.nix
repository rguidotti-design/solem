{ config, pkgs, lib, ... }:

# SOLEM OFFICE — suite ufficio FOSS (alternativa Microsoft 365).
#
# Single responsibility: SOLO installazione applicativi office +
# OnlyOffice Document Server self-host opt-in.
#
# Stack:
#   LibreOffice 24+ (Writer/Calc/Impress/Draw/Base/Math) — default
#   OnlyOffice Desktop (più compatibile con .docx/xlsx complessi)
#   Calligra Suite (KDE) — opt
#   OnlyOffice Document Server — self-host collab real-time, opt

let
  cfg = config.solem.office;
in {
  options.solem.office = {
    enable = lib.mkEnableOption "Suite ufficio FOSS (LibreOffice + OnlyOffice)";

    libreOffice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "LibreOffice Fresh (più aggiornato)";
    };

    onlyOfficeDesktop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "OnlyOffice Desktop (compatibilità DOCX/XLSX migliore)";
    };

    onlyOfficeServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "OnlyOffice Document Server self-host (collab real-time)";
    };

    calligra = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Calligra KDE alternative";
    };

    italianDictionary = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Dizionario italiano + grammatica (hunspell-it + LanguageTool)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      (lib.optionals cfg.libreOffice [
        libreoffice-fresh
        hunspell
      ])
      ++ (lib.optional cfg.onlyOfficeDesktop onlyoffice-bin)
      ++ (lib.optionals cfg.calligra [
        kdePackages.calligra
      ])
      ++ (lib.optionals cfg.italianDictionary [
        hunspellDicts.it_IT
        hunspellDicts.en_US
        languagetool   # grammar checker offline
      ]);

    # OnlyOffice Document Server (collab real-time tipo Google Docs)
    services.onlyoffice = lib.mkIf cfg.onlyOfficeServer {
      enable = true;
      port = 8888;
    };
  };
}
