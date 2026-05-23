{ config, pkgs, lib, ... }:

# SOLEM PAPERLESS — archivio documenti OCR self-host (Paperless-ngx).
#
# Single responsibility: SOLO orchestrare paperless-ngx service:
# - OCR multi-lingua (Tesseract) inclusa lingua italiana
# - Tag automatici + ML classification
# - Web UI per archivio digitale (fatture, bollette, contratti)
# - Consumer folder: copia un PDF lì → indicizzato automaticamente
#
# Tutto FOSS (GPL-3.0). Costo: 0 €.
# Alternativa privacy-friendly a servizi cloud SaaS (Evernote, OneDrive paper).

let
  cfg = config.solem.paperless;
in {
  options.solem.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx self-host (archivio documenti OCR)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 28981;
      description = "Porta HTTP web UI (default 28981 standard Paperless)";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/paperless";
      description = "Directory dati (consumer/, media/, originals/)";
    };

    languages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ita" "eng" ];
      description = ''
        Lingue OCR (Tesseract). Default: italiano + inglese.
        Aggiungi 'deu', 'fra', 'spa' per altri.
      '';
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File contenente password admin (per sops-nix). Se null,
        genera prima esecuzione via `paperless-ngx createsuperuser`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = true;
      port = cfg.port;
      dataDir = cfg.dataDir;
      address = "127.0.0.1";   # solo locale; usa caddy/nginx reverse proxy
      passwordFile = cfg.adminPasswordFile;

      settings = {
        # Lingue OCR
        PAPERLESS_OCR_LANGUAGE = lib.concatStringsSep "+" cfg.languages;

        # Tag automatici via ML
        PAPERLESS_ENABLE_NLTK = true;

        # Consumer folder
        PAPERLESS_CONSUMER_POLLING = 5;
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;

        # Time zone
        PAPERLESS_TIME_ZONE = "Europe/Rome";

        # OCR mode: skip se già testo, altrimenti force
        PAPERLESS_OCR_MODE = "skip";

        # Workers limitati (CPU)
        PAPERLESS_TASK_WORKERS = 2;
        PAPERLESS_THREADS_PER_WORKER = 2;

        # URL
        PAPERLESS_URL = "http://localhost:${toString cfg.port}";
      };
    };

    # CLI helper per drop documento da terminale
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "solem-archive";
        runtimeInputs = [ coreutils ];
        text = ''
          SRC="''${1:?Usage: solem-archive <file.pdf>}"
          DEST="${cfg.dataDir}/consumer/"
          if [[ ! -d "$DEST" ]]; then
            echo "Consumer folder $DEST non esiste — Paperless non avviato?"
            exit 1
          fi
          cp "$SRC" "$DEST"
          echo "OK → ingest in 5s su http://localhost:${toString cfg.port}"
        '';
      })
    ];
  };
}
