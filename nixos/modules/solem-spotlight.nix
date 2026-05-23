{ config, pkgs, lib, ... }:

# SOLEM SPOTLIGHT — global search Spotlight-style (Super+Space).
#
# Single responsibility: SOLO orchestrare launcher universale FOSS:
# - Anyrun     → Rust, plugin-based, Wayland-first (raccomandato)
# - Albert     → Qt, mature, plugin python (alternativa)
# - Rofi/Wofi  → minimal, Vim-style
# - krunner    → KDE, integrato (per chi usa Plasma)
#
# Plugin abilitati:
# - applications (lancia desktop entries)
# - files       (find recente)
# - calculator  (operazioni matematiche)
# - shell       (esegui comando)
# - kidex       (file indexer rust)
# - gavio       (query GAVIO da launcher!)
#
# Tutto FOSS, 0 €. Risponde al gap "Spotlight macOS" della COMPETITIVE-GAP.md.

let
  cfg = config.solem.spotlight;

  # Plugin custom anyrun per query GAVIO direttamente dal launcher
  gavioPlugin = pkgs.writeShellApplication {
    name = "solem-spotlight-gavio";
    runtimeInputs = with pkgs; [ curl jq coreutils ];
    text = ''
      # Esegue una query a GAVIO via API locale.
      # Uso: solem-spotlight-gavio "domanda"
      Q="''${1:?Usage: solem-spotlight-gavio <query>}"
      GAVIO_URL="''${GAVIO_API_URL:-http://127.0.0.1:8000}"
      RESPONSE=$(curl -s -X POST "$GAVIO_URL/v2/agent/query" \
        -H "Content-Type: application/json" \
        -d "{\"query\": $(jq -Rs . <<< "$Q")}" || echo '{"response":"GAVIO offline"}')
      echo "$RESPONSE" | jq -r '.response // .answer // "(no response)"'
    '';
  };

  # Anyrun config minimale
  anyrunConfig = pkgs.writeText "anyrun-config.ron" ''
    Config(
      x: Fraction(0.5),
      y: Fraction(0.3),
      width: Absolute(800),
      height: Absolute(0),
      hide_icons: false,
      ignore_exclusive_zones: false,
      layer: Overlay,
      hide_plugin_info: false,
      close_on_click: true,
      show_results_immediately: false,
      max_entries: Some(10),
      plugins: [
        "libapplications.so",
        "libsymbols.so",
        "libshell.so",
        "librink.so",
        "libtranslate.so",
      ],
    )
  '';
in {
  options.solem.spotlight = {
    enable = lib.mkEnableOption "Global search Spotlight-style (Anyrun/Albert)";

    launcher = lib.mkOption {
      type = lib.types.enum [ "anyrun" "albert" "rofi" "krunner" ];
      default = "anyrun";
      description = "Quale launcher usare come default (Super+Space)";
    };

    gavioIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Aggiungi shortcut per query GAVIO dal launcher (`g: domanda`)";
    };

    keybind = lib.mkOption {
      type = lib.types.str;
      default = "SUPER, space";
      description = "Hyprland bind. Default: Super+Space (come macOS Spotlight)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        # Sempre presente: indexer file Rust
        # kidex      # solo se in nixpkgs stabile, sennò recoll
        recoll        # file content indexer mature
        fzf
        skim          # alternativa Rust
      ]

      (lib.optionals (cfg.launcher == "anyrun") [
        anyrun
      ])

      (lib.optionals (cfg.launcher == "albert") [
        albert
      ])

      (lib.optionals (cfg.launcher == "rofi") [
        rofi-wayland
        rofi-calc
        rofi-emoji
        rofi-power-menu
      ])

      (lib.optionals cfg.gavioIntegration [
        gavioPlugin
      ])
    ];

    # Hyprland bind se desktop Hyprland attivo
    # (configurazione live in ~/.config/hypr/hyprland.conf o sezione utente)
    # Suggerimento via environment.etc per documentazione live
    environment.etc."solem/spotlight.hint".text = ''
      # SOLEM SPOTLIGHT
      # Launcher attivo: ${cfg.launcher}
      # Tasto: ${cfg.keybind}
      #
      # Aggiungi al tuo hyprland.conf:
      #   bind = ${cfg.keybind}, exec, ${cfg.launcher}
      #
      ${lib.optionalString cfg.gavioIntegration ''
        # GAVIO query: scrivi "g: la tua domanda" dentro al launcher
        # (richiede plugin shell + comando solem-spotlight-gavio)
      ''}
    '';

    # Albert è una app userspace; lanciala manualmente da hyprland.conf.
  };
}
