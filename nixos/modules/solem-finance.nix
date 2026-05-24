{ config, pkgs, lib, ... }:

# SOLEM FINANCE — personal finance (alternativa Mint/QuickBooks).
#
# Single responsibility: SOLO installazione tool finance FOSS:
#   GnuCash    → double-entry accounting GUI
#   Firefly III → personal finance web (self-host)
#   ledger CLI → plain-text accounting per power user
#   beancount  → ledger-alike Python-based
#   actual     → budget envelope self-host (alternativa YNAB)

let
  cfg = config.solem.finance;
in {
  options.solem.finance = {
    gnucash = lib.mkEnableOption "GnuCash GUI accounting";

    fireflyIii = {
      enable = lib.mkEnableOption "Firefly III personal finance web";
      port = lib.mkOption { type = lib.types.port; default = 8082; };
    };

    actual = {
      enable = lib.mkEnableOption "Actual Budget (envelope budgeting self-host)";
      port = lib.mkOption { type = lib.types.port; default = 5006; };
    };

    ledger = lib.mkEnableOption "ledger + beancount CLI (plain-text accounting)";

    italianTax = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tool calcolo IRPEF + IVA italiani (script bash)";
    };
  };

  config = lib.mkIf (cfg.gnucash || cfg.ledger || cfg.fireflyIii.enable || cfg.actual.enable) {
    environment.systemPackages = with pkgs; lib.flatten [
      (lib.optional cfg.gnucash gnucash)
      (lib.optionals cfg.ledger [
        ledger
        hledger
        beancount
        fava           # GUI web per beancount
      ])
    ];

    # Firefly III
    services.firefly-iii = lib.mkIf cfg.fireflyIii.enable {
      enable = true;
      settings.APP_URL = "http://finance.solem.local:${toString cfg.fireflyIii.port}";
    };

    # Actual Budget
    services.actual = lib.mkIf cfg.actual.enable {
      enable = true;
      settings = {
        port = cfg.actual.port;
        hostname = "0.0.0.0";
      };
    };

    # Italian tax helper
    environment.etc."solem/italian-tax-quick.md" = lib.mkIf cfg.italianTax {
      text = ''
        # SOLEM — Quick Italian Tax helpers

        ## IVA 22% (standard)
        echo "scale=2; 100 * 1.22" | bc          # da prezzo netto a lordo
        echo "scale=2; 122 / 1.22" | bc          # da prezzo lordo a netto
        echo "scale=2; 122 - (122 / 1.22)" | bc  # quanto di IVA

        ## IRPEF aliquote 2026 (scaglioni)
        # Fino a 28.000  → 23%
        # 28.000–50.000  → 35%
        # Oltre 50.000   → 43%

        ## Forfettario 5%/15% (P.IVA fino 85k)
        # Coefficiente redditività dipende dal codice ATECO.

        ## Contributi INPS gestione separata (2026)
        # Aliquota: 26.07% (con DIS-COLL)
        # Massimale annuo: 119.650 €

        Per calcolo preciso: solem-app install Conty / Tenuta Conti.
      '';
    };
  };
}
