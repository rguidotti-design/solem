{ config, pkgs, lib, ... }:

# SOLEM TYPOGRAPHY — toolkit "scrittura tecnica/editoriale" 100% FOSS.
#
# Single responsibility: SOLO motori di typesetting/markdown/docs FOSS:
# - Typst   → moderno, Rust, sostituto LaTeX (compile in ms)
# - Pandoc  → conversione universale documento ↔ documento
# - Quarto  → publishing scientifico (libri, paper, slides)
# - Marp    → markdown → slide PPT/PDF/HTML
# - Asciidoctor → tecnical writing pro
# - LaTeX (TeX Live) opt-in (pesante 4 GB)
# - mdBook  → libri tech con Rust
#
# CLI `solem-doc` per conversione rapida. Tutto FOSS, 0 €.

let
  cfg = config.solem.typography;

  docCli = pkgs.writeShellApplication {
    name = "solem-doc";
    runtimeInputs = with pkgs; [ pandoc typst coreutils ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        md2pdf)
          SRC="''${2:?Usage: solem-doc md2pdf <input.md>}"
          pandoc "$SRC" -o "''${SRC%.md}.pdf" --pdf-engine=xelatex 2>/dev/null \
            || pandoc "$SRC" -o "''${SRC%.md}.pdf" --pdf-engine=tectonic 2>/dev/null \
            || pandoc "$SRC" -o "''${SRC%.md}.pdf"
          echo "→ ''${SRC%.md}.pdf"
          ;;
        md2docx)
          SRC="''${2:?Usage: solem-doc md2docx <input.md>}"
          pandoc "$SRC" -o "''${SRC%.md}.docx"
          ;;
        md2html)
          SRC="''${2:?Usage: solem-doc md2html <input.md>}"
          pandoc "$SRC" -o "''${SRC%.md}.html" --standalone --toc
          ;;
        md2epub)
          SRC="''${2:?Usage: solem-doc md2epub <input.md>}"
          pandoc "$SRC" -o "''${SRC%.md}.epub"
          ;;
        docx2md)
          SRC="''${2:?Usage: solem-doc docx2md <input.docx>}"
          pandoc "$SRC" -o "''${SRC%.docx}.md"
          ;;
        typst)
          SRC="''${2:?Usage: solem-doc typst <file.typ>}"
          typst compile "$SRC"
          ;;
        watch-typst)
          SRC="''${2:?Usage: solem-doc watch-typst <file.typ>}"
          typst watch "$SRC"
          ;;
        slides)
          SRC="''${2:?Usage: solem-doc slides <input.md>}"
          pandoc -t revealjs --standalone -V theme=white -o "''${SRC%.md}-slides.html" "$SRC"
          ;;
        wordcount|wc)
          SRC="''${2:?Usage: solem-doc wordcount <input.md>}"
          pandoc "$SRC" -t plain | wc -w
          ;;
        *)
          echo "solem-doc — toolkit typesetting FOSS"
          echo
          echo "  Markdown:"
          echo "    solem-doc md2pdf <f.md>     md → PDF"
          echo "    solem-doc md2docx <f.md>    md → DOCX (Word)"
          echo "    solem-doc md2html <f.md>    md → HTML standalone + TOC"
          echo "    solem-doc md2epub <f.md>    md → EPUB e-book"
          echo "    solem-doc slides <f.md>     md → slide RevealJS"
          echo "    solem-doc wc <f.md>         conta parole"
          echo
          echo "  DOCX → markdown:"
          echo "    solem-doc docx2md <f.docx>"
          echo
          echo "  Typst (moderno LaTeX-alt):"
          echo "    solem-doc typst <f.typ>             compile one-shot"
          echo "    solem-doc watch-typst <f.typ>       live reload"
          ;;
      esac
    '';
  };
in {
  options.solem.typography = {
    enable = lib.mkEnableOption "Toolkit typography FOSS (Typst, Pandoc, Quarto, Marp, Asciidoctor)";

    latex = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Installa TeX Live full scheme-medium (~ 4 GB). Off di default per
        peso. Typst è preferito (più veloce, sintassi moderna).
      '';
    };

    quarto = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Quarto — publishing scientifico (libri, paper, slide, dashboard)";
    };

    marp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Marp CLI — slide markdown → PPT/PDF/HTML";
    };

    asciidoc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Asciidoctor + extension — technical writing standard pro";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        docCli

        # Pandoc (universale)
        pandoc

        # Typst (Rust, moderno)
        typst
        typstfmt

        # mdBook (Rust books)
        mdbook
        mdbook-mermaid
        mdbook-toc

        # Tectonic (LaTeX leggero on-demand)
        tectonic
      ]

      (lib.optionals cfg.latex [
        # TeX Live medium scheme (peso accettabile, no full)
        texlive.combined.scheme-medium
      ])

      (lib.optionals cfg.quarto [
        quarto
      ])

      (lib.optionals cfg.marp [
        marp-cli
      ])

      (lib.optionals cfg.asciidoc [
        asciidoctor
        asciidoctor-with-extensions
      ])
    ];
  };
}
