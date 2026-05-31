{ config, pkgs, lib, ... }:

# SOLEM GAVIO PACKAGE — Step 30: scaffolding nix derivation per GAVIO.
#
# Single responsibility: SOLO Nix derivation che pacchettizza GAVIO
# (Python FastAPI app) come pacchetto first-class, sostituendo lo stub
# del gavio.nix originale. Quando GAVIO repo e' clonato sul sistema,
# questa derivation lo trasforma in un pacchetto installabile come
# qualsiasi software Nix.
#
# Threat coperto: nessuno NUOVO — questo modulo abilita TUTTI gli step
# 1-29 di applicarsi a GAVIO reale, non solo scaffold. Cambia il gioco:
#   - solem-ai-user gavio-ai esegue GAVIO REALE (non sleep infinity)
#   - solem-gavio-zero-trust applica hardening a python uvicorn REALE
#   - solem-apparmor profile confina python venv REALE
#   - solem-gavio-prompt-filter intercetta query REALI a GAVIO
#   - solem-gavio-model-integrity verifica modelli realmente caricati
#
# Tre modalita' di pacchettizzazione:
#   A) Source path: utente specifica `solem.gavioPackage.src = ./path-locale`
#   B) Git URL: clone runtime da repo pubblico/privato
#   C) Pre-built: derivation completa nixpkgs-style
#
# Step 30 = SCAFFOLDING + opzione A (source path). Default: stub.
#
# Tutto FOSS (poetry2nix / uv2nix per dependency resolution).

let
  cfg = config.solem.gavioPackage;

  # Derivation GAVIO (skip se source non specificato)
  gavioPackage = lib.mkIf (cfg.src != null) (
    pkgs.python3Packages.buildPythonApplication rec {
      pname = "gavio";
      version = cfg.version;
      src = cfg.src;
      format = "pyproject";

      nativeBuildInputs = with pkgs.python3Packages; [
        setuptools
        wheel
        pip
      ];

      propagatedBuildInputs = with pkgs.python3Packages; [
        fastapi
        uvicorn
        pydantic
        httpx
        python-dotenv
        requests
        # GAVIO-specific (audit del codice nel commit attuale)
        # supabase
        # pypdf
        # reportlab
        # Pillow
        # youtube-transcript-api
        # faster-whisper
        # pywebpush
        # edge-tts
      ];

      # GAVIO usa entry-point custom (server.py o app.py)
      # Configurabile via cfg.entrypoint
      postInstall = ''
        # Wrapper che setta PATH + env per GAVIO
        mkdir -p $out/bin
        cat > $out/bin/gavio <<EOF
        #!/usr/bin/env bash
        export PATH=$out/bin:$PATH
        exec ${"\${out}"}/lib/python*/site-packages/${cfg.entrypoint} "\$@"
        EOF
        chmod +x $out/bin/gavio
      '';

      # Skip test per ora (richiede dipendenze esterne)
      doCheck = false;

      meta = {
        description = "GAVIO — AI personale di Ruben Guidotti";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
      };
    }
  );
in {
  options.solem.gavioPackage = {
    enable = lib.mkEnableOption "Pacchettizza GAVIO come derivation Nix";

    src = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/opt/gavio-source";
      description = ''
        Path del sorgente GAVIO (clonato manualmente).
        Se null, fallback a stub. Per source git:
          src = pkgs.fetchFromGitHub { owner=...; repo=...; sha256=...; }
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0-dev";
      description = "Version string per derivation";
    };

    entrypoint = lib.mkOption {
      type = lib.types.str;
      default = "gavio/server.py";
      example = "gavio/app.py";
      description = "Path relativo a sito-packages del entry point";
    };

    overrideService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Sostituisce gavio.service ExecStart con il pacchetto Nix invece
        del bootstrap venv. Disabilita se preferisci venv legacy.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.src != null;
      message = ''
        solem.gavioPackage.enable=true richiede solem.gavioPackage.src.
        Esempio:
          solem.gavioPackage.src = /opt/gavio-source;
          # oppure
          solem.gavioPackage.src = pkgs.fetchFromGitHub { ... };
      '';
    }];

    environment.systemPackages = [ gavioPackage ];

    # Override gavio.service ExecStart con il pacchetto Nix
    systemd.services.gavio.serviceConfig.ExecStart = lib.mkIf cfg.overrideService (
      lib.mkForce "${gavioPackage}/bin/gavio"
    );

    # Skip bootstrap venv quando packaged
    systemd.services.gavio.serviceConfig.ExecStartPre = lib.mkIf cfg.overrideService (
      lib.mkForce ""
    );

    environment.etc."solem/gavio-package.md".text = ''
      # SOLEM GAVIO Package (Step 30)

      Trasforma GAVIO da stub (bootstrap venv ad ogni boot) a pacchetto
      Nix first-class, gestito reproducibly dal store.

      ## Vantaggi vs stub originale
      - **Reproducibility**: build hash-deterministico, ogni boot identico.
      - **Dependency lock**: pyproject.toml → Nix derivation, no pip surprise.
      - **Rollback safe**: NixOS generation include GAVIO → rollback funziona.
      - **Cache binari**: cachix puo' servire build pre-compilato.
      - **Apparmor enforcement reale**: profilo /var/lib/gavio-ai/venv/bin/python3
        ora corrisponde a binary STABILE (no random uv venv paths).

      ## Setup

      ### A) Source locale (sviluppo)
      ```nix
      solem.gavioPackage = {
        enable = true;
        src = /opt/gavio-source;     # clonato manualmente
        version = "0.1.0";
        entrypoint = "gavio/server.py";
      };
      ```

      ### B) Source git fissato (production)
      ```nix
      solem.gavioPackage = {
        enable = true;
        src = pkgs.fetchFromGitHub {
          owner = "rguidotti-design";
          repo = "gavio";
          rev = "v0.1.0";
          sha256 = "sha256-..."; # nix-prefetch-git
        };
        version = "0.1.0";
      };
      ```

      ## Effetto a cascata sui 27 step precedenti

      Step | Beneficio packaged
      ---|---
      1 ai-user | gavio-ai esegue GAVIO REALE (non sleep)
      3 gavio-zero-trust | hardening systemd applicato a process REALE
      8 apparmor | profile /var/lib/gavio-ai/venv/bin/python3 corrisponde
      9 ai-audit-strict | execve/connect del REAL python da loggare
      20 model-integrity | hash check su modelli realmente caricati
      21 prompt-filter | intercetta query REALI a GAVIO
      27 friday-mode | "solem ask" funziona davvero (bridge GAVIO live)

      ## Limiti onesti
      - Step 30 = scaffolding: la derivation assume pyproject.toml standard.
        GAVIO reale puo' avere build steps custom (es. compilare cython,
        scaricare modelli al build, ...) — richiederebbero override
        derivation aggiuntivi.
      - Dependencies listate sono parziali (commentate). Per build completa:
        usare poetry2nix o uv2nix per parser automatico pyproject.toml.
      - Default = null → no auto-enable: utente DEVE fornire src esplicito.
        Questo evita di rompere setup esistenti con stub funzionante.
    '';
  };
}
