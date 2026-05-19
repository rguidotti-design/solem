{ config, pkgs, lib, ... }:

let
  cfg = config.solem.creator;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM CREATOR — toolkit per creare QUALSIASI COSA
  # ──────────────────────────────────────────────────────────────────────
  # Filosofia spec founder: "Costruttore-friendly per natura. Creare > consumare."
  #
  # 4 toolset opt-in indipendenti:
  #
  #   1. dev         — linguaggi + IDE CLI (Python/Go/Rust/Node/Zig)
  #   2. ai          — Jupyter, ML libs, modelli Ollama auto-pull, GPU support
  #   3. data        — DB client, ETL, jq/yq, parquet, pandas
  #   4. creative    — image/audio/video editing, 3D, CAD
  #
  # Default: 'dev' attivo, gli altri opt-in. Cambia con:
  #   solem.creator.dev.enable = true;
  #   solem.creator.ai.enable = true;

  options.solem.creator = {
    dev = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Toolkit sviluppo (linguaggi + tool CLI).";
      };
      languages = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "python" "node" "go" "rust" "zig" "deno" "lua" "ruby" "java" ]);
        default = [ "python" "node" "go" "rust" ];
        description = "Linguaggi installati system-wide.";
      };
    };

    ai = {
      enable = lib.mkEnableOption "Toolkit AI (Jupyter, ML libs, modelli Ollama)";
      pullModels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];  # esempio: [ "llama3.2:3b" "nomic-embed-text" ]
        description = "Modelli Ollama da pre-scaricare al primo boot.";
      };
      cudaSupport = lib.mkEnableOption "Build pacchetti AI con supporto CUDA (richiede NVIDIA)";
    };

    data = lib.mkEnableOption "Toolkit data (DB client, ETL, parquet, pandas, duckdb)";

    creative = lib.mkEnableOption "Toolkit creativo (imagemagick, ffmpeg, blender, audacity, freecad)";
  };

  config = lib.mkMerge [
    # ── 1. DEV ──────────────────────────────────────────────────────
    (lib.mkIf cfg.dev.enable {
      environment.systemPackages = with pkgs;
        # Tool universali
        [
          # Editor
          vim neovim helix
          # Multiplexer + prompt
          tmux zellij starship fish
          # Git extras
          gh lazygit git-lfs git-crypt delta
          # Build / make
          gnumake cmake meson ninja
          # Util CLI moderni
          ripgrep fd bat eza fzf zoxide
          jq yq httpie
          # Container
          podman buildah skopeo
          kubectl k9s helm
          # Network / debug
          dig mtr nmap tcpdump
          # Performance
          hyperfine bandwhich bottom
          # IaC — opentofu (fork OSS di terraform; terraform BSL non sempre disponibile)
          opentofu ansible
        ]
        # Linguaggi opt-in
        ++ lib.optionals (builtins.elem "python" cfg.dev.languages) [
          python312 uv ruff python312Packages.ipython
        ]
        ++ lib.optionals (builtins.elem "node" cfg.dev.languages) [
          nodejs_22 pnpm bun
        ]
        ++ lib.optionals (builtins.elem "go" cfg.dev.languages) [
          go gopls
        ]
        ++ lib.optionals (builtins.elem "rust" cfg.dev.languages) [
          rustc cargo rustfmt clippy rust-analyzer
        ]
        ++ lib.optionals (builtins.elem "zig" cfg.dev.languages) [ zig ]
        ++ lib.optionals (builtins.elem "deno" cfg.dev.languages) [ deno ]
        ++ lib.optionals (builtins.elem "lua" cfg.dev.languages) [ lua luajit ]
        ++ lib.optionals (builtins.elem "ruby" cfg.dev.languages) [ ruby ]
        ++ lib.optionals (builtins.elem "java" cfg.dev.languages) [ jdk21 maven gradle ];
    })

    # ── 2. AI ───────────────────────────────────────────────────────
    (lib.mkIf cfg.ai.enable {
      environment.systemPackages = with pkgs; [
        # Jupyter + interactive
        python312Packages.jupyterlab
        python312Packages.ipykernel
        python312Packages.notebook
        # ML core
        python312Packages.numpy
        python312Packages.pandas
        python312Packages.scikit-learn
        python312Packages.matplotlib
        python312Packages.seaborn
        # LLM client
        python312Packages.openai
        python312Packages.anthropic
        python312Packages.transformers
        python312Packages.sentence-transformers
        # Vector DB CLI
        python312Packages.chromadb
        # Embedding
        python312Packages.tiktoken
      ];

      # Ollama già installato da gavio.nix — qui solo pre-pull modelli
      services.ollama.loadModels = lib.mkIf (cfg.ai.pullModels != [ ]) cfg.ai.pullModels;

      # CUDA opt-in (richiede driver NVIDIA, configurabile in hardware.nix)
      nixpkgs.config.cudaSupport = lib.mkIf cfg.ai.cudaSupport true;
    })

    # ── 3. DATA ─────────────────────────────────────────────────────
    (lib.mkIf cfg.data {
      environment.systemPackages = with pkgs; [
        # DB client
        postgresql_16  # psql
        sqlite
        # ETL / analytics
        duckdb
        # Python data
        python312Packages.polars
        python312Packages.pyarrow
        python312Packages.duckdb
        # Format conversion
        miller    # mlr — csv/tsv/json swiss army knife
      ];
    })

    # ── 4. CREATIVE ─────────────────────────────────────────────────
    (lib.mkIf cfg.creative {
      environment.systemPackages = with pkgs; [
        # Image
        imagemagick
        gimp
        inkscape
        # Audio / Video (ffmpeg già in gavio.nix)
        audacity
        # 3D / CAD
        blender
        freecad
        # OCR (oltre tesseract già installato)
        ocrmypdf
      ];
    })
  ];
}
