{ config, pkgs, lib, ... }:

# SOLEM PRINT PDF — stampa virtuale "Save as PDF" da qualsiasi app.
#
# Single responsibility: SOLO setup CUPS-PDF (FOSS GPL) come stampante
# virtuale che salva in ~/Documents/PDFs/. Equivale a Windows "Microsoft
# Print to PDF" e macOS "Save as PDF" built-in.

let
  cfg = config.solem.printPdf;
in {
  options.solem.printPdf = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa stampante virtuale 'PDF' (CUPS-PDF FOSS)";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Documents/PDFs";
      description = "Cartella output PDF (relativa a $HOME utente)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      cups-pdf.enable = true;
    };

    environment.systemPackages = with pkgs; [
      cups-pdf-to-pdf       # post-process PDF (qpdf-based)
    ];

    # Info per utente
    environment.etc."solem/print-pdf.txt".text = ''
      SOLEM Print PDF — stampante virtuale FOSS

      Come usarla:
        1. Apri qualsiasi app (Firefox, LibreOffice, ecc.)
        2. File → Stampa → seleziona stampante "PDF"
        3. Print
        4. PDF salvato in ~/PDF/ (default CUPS-PDF)

      Sostituisce:
        - Windows "Microsoft Print to PDF" (built-in)
        - macOS "Save as PDF..." (built-in)

      FOSS: CUPS-PDF + qpdf (entrambi GPL).
    '';
  };
}
