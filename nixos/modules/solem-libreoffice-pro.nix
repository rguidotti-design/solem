{ config, pkgs, lib, ... }:

# SOLEM LIBREOFFICE PRO — LibreOffice + estensioni IT + LanguageTool.
#
# Single responsibility: SOLO LibreOffice + plugin Italian + Zotero +
# LanguageTool integration. Configurazione coerente per uso pro.

let
  cfg = config.solem.libreofficePro;
in {
  options.solem.libreofficePro = {
    enable = lib.mkEnableOption "LibreOffice Pro (estensioni IT + LanguageTool + Zotero)";

    onlyoffice = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa anche OnlyOffice Desktop (compat MS Office migliore, AGPL)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        libreoffice-qt6-fresh             # versione più recente
        hunspellDicts.it_IT
        hunspellDicts.en_US
        languagetool                     # grammatica avanzata IT (Java)
        zotero                           # bibliografia
        pandoc                           # conversione documenti
      ]

      (lib.optionals cfg.onlyoffice [
        onlyoffice-bin
      ])
    ];

    # LanguageTool come servizio locale (porta 8010, consumed da LibreOffice)
    services.languagetool = {
      enable = true;
      port = 8010;
    };
  };
}
