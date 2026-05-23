{ config, pkgs, lib, ... }:

# SOLEM READERS — RSS, e-book, knowledge tools 100% FOSS.
#
# Single responsibility: SOLO lettura/knowledge FOSS:
# - RSS reader (Newsboat TUI + Liferea GUI + opzionale FreshRSS self-host)
# - E-book (Calibre, Foliate, MuPDF, koreader-emulator)
# - Wiki personale (Logseq, Joplin, Obsidian-alt Anytype)
# - Spaced-repetition (Anki + minor-anki addons)
# - Read-it-later (Wallabag self-host opzionale)
#
# Tutto FOSS. 0 €.

let
  cfg = config.solem.readers;
in {
  options.solem.readers = {
    enable = lib.mkEnableOption "Reader stack FOSS (RSS, e-book, knowledge, SRS)";

    freshrss = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "FreshRSS self-host (PHP + nginx) — RSS aggregator multi-device";
    };

    wallabag = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Wallabag self-host — read-it-later FOSS (alt Pocket)";
    };

    miniflux = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Miniflux self-host — RSS reader minimalista (Go binary, PostgreSQL).
        Alternativa a FreshRSS. Più leggero, single binary.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        # RSS desktop
        newsboat          # TUI RSS reader (config Vim-style)
        liferea           # GTK RSS reader (GUI)

        # E-book
        calibre           # gestione e-book completa
        foliate           # epub reader GTK
        mupdf             # PDF leggerissimo
        zathura           # PDF Vim-style + DjVu/CBZ via plugin
        sioyek            # PDF per paper accademici (FOSS GPL)
        okular            # KDE multi-format

        # Knowledge / note (solo FOSS puri)
        logseq            # outliner + grafo, AGPL
        joplin-desktop    # markdown notes + sync E2EE
        zim               # wiki personale GTK
        # NOTA: Anytype escluso (source-available BSL, NON FOSS pura).

        # Spaced repetition
        anki              # Anki classico (AGPL)

        # Read-it-later locale
        wallabag-client   # CLI Wallabag (server opt-in sotto)

        # Knowledge graph
        zotero            # gestione bibliografica (AGPL)
      ];
    }

    # FreshRSS self-host (PHP, leggero)
    (lib.mkIf cfg.freshrss {
      services.freshrss = {
        enable = true;
        baseUrl = "http://localhost";
        defaultUser = "solem";
        passwordFile = "/var/lib/freshrss/password";
      };
    })

    # Miniflux self-host (Go, ancora più leggero)
    (lib.mkIf cfg.miniflux {
      services.miniflux = {
        enable = true;
        config = {
          LISTEN_ADDR = "127.0.0.1:8090";
          BASE_URL = "http://localhost:8090";
        };
      };
    })

    # Wallabag self-host (read-it-later)
    (lib.mkIf cfg.wallabag {
      # Wallabag NixOS module: solo se disponibile. Altrimenti via docker.
      # Per ora segnalo come future-work — manteniamo opzione registrata.
      warnings = [
        "Wallabag self-host: in NixOS 24.11 services.wallabag potrebbe non essere stabile. Considera podman + immagine ufficiale."
      ];
    })
  ]);
}
