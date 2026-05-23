{ config, pkgs, lib, ... }:

# SOLEM DEVELOPER EXTRAS — tool dev aggiuntivi 100% FOSS.
#
# Single responsibility: SOLO tool dev FOSS non-language-specific:
# API testing (Bruno, Insomnia open-source), static site (Hugo, Zola,
# Pelican, mdBook), CLI per code-forge FOSS (tea per Forgejo/Gitea,
# glab per GitLab), DB client (DBeaver, beekeeper-studio), container
# (podman + buildah + skopeo), reverse proxy (caddy, nginx).
#
# Niente strumenti SaaS-locked o closed-source. Costo: 0 €.

let
  cfg = config.solem.developerExtras;
in {
  options.solem.developerExtras = {
    enable = lib.mkEnableOption "Tool dev extra (API testing, static-site, DB, container, proxy)";

    api = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tool per API testing FOSS (Bruno, Insomnia OSS, httpie, curlie)";
    };

    staticSite = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Static-site generator FOSS (Hugo, Zola, mdBook, Pelican)";
    };

    forge = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "CLI per code-forge FOSS (tea per Forgejo/Gitea, glab per GitLab CE)";
    };

    database = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Client DB FOSS (DBeaver CE, pgAdmin4, sqlitebrowser, usql)";
    };

    container = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Container tooling FOSS (podman, buildah, skopeo, dive)";
    };

    proxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reverse proxy local-dev (caddy + nginx + mkcert)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [

      # API testing FOSS
      (lib.optionals cfg.api [
        bruno         # FOSS, MIT — alternativa Postman, offline-first
        httpie        # CLI HTTP client
        curlie        # curl + httpie ibrido
        xh            # Rust HTTPie reimplementation
        grpcurl       # gRPC CLI
        websocat      # WebSocket CLI
      ])

      # Static-site generator FOSS
      (lib.optionals cfg.staticSite [
        hugo          # Go, fast static-site
        zola          # Rust, single-binary
        pelican       # Python static-site
        mdbook        # Rust, libri/docs in Markdown
        hut           # SourceHut CLI (FOSS forge)
      ])

      # Forge CLI FOSS
      (lib.optionals cfg.forge [
        tea           # Forgejo / Gitea CLI
        glab          # GitLab CLI (works con GitLab CE self-host)
        gh            # GitHub CLI (compatibile con Forgejo via API)
      ])

      # Database client FOSS
      (lib.optionals cfg.database [
        dbeaver-bin       # CE Apache-2.0
        pgadmin4          # PostgreSQL admin
        sqlitebrowser     # GPL, SQLite GUI
        usql              # universal SQL CLI (FOSS)
        mycli             # MySQL/MariaDB CLI with autocomplete
        pgcli             # PostgreSQL CLI
        litecli           # SQLite CLI
        redis             # redis-cli incluso
      ])

      # Container tooling FOSS (NO Docker Desktop closed)
      (lib.optionals cfg.container [
        podman
        podman-compose
        buildah
        skopeo
        dive          # analizza layer container
        ctop          # top per container
        lazydocker    # TUI podman-compatible
      ])

      # Reverse proxy locale per dev
      (lib.optionals cfg.proxy [
        caddy
        nginx
        mkcert        # TLS locale per dev
      ])

    ];

    # Podman come Docker-compatible (rootless di default)
    virtualisation.podman = lib.mkIf cfg.container {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
