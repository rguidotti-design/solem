{ config, pkgs, lib, ... }:

# SOLEM QUICK SEARCH — ricerca universale CLI Spotlight-like.
#
# Single responsibility: SOLO CLI `solem-find` che cerca:
# - File nel filesystem ($HOME)
# - Pacchetti installati
# - Comandi (PATH)
# - Servizi systemd
# - Apertura veloce: file, URL, web search via solem-api
#
# Niente GUI launcher dependency. Solo coreutils + fd + ripgrep + fzf.

let
  cfg = config.solem.quickSearch;

  searchCli = pkgs.writeShellApplication {
    name = "solem-find";
    runtimeInputs = with pkgs; [ coreutils fd ripgrep fzf systemd ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in

        # ── FILE search (fd, fast) ────────────────────────────────────
        file|files)
          Q="''${1:?Usage: solem-find file <name-pattern>}"
          fd "$Q" "''${HOME:-/}" 2>/dev/null | head -50
          ;;

        # ── CONTENT search (ripgrep) ──────────────────────────────────
        text|content|grep)
          Q="''${1:?Usage: solem-find text <pattern> [dir]}"
          DIR="''${2:-$HOME}"
          rg -l "$Q" "$DIR" 2>/dev/null | head -30
          ;;

        # ── COMMAND search (PATH) ─────────────────────────────────────
        cmd|command|which)
          Q="''${1:?Usage: solem-find cmd <name>}"
          for dir in $(echo "$PATH" | tr ':' ' '); do
            ls -1 "$dir" 2>/dev/null | grep -i "$Q" | sed "s|^|$dir/|" | head -10
          done
          ;;

        # ── PACKAGE search (nix-store) ────────────────────────────────
        pkg|package)
          Q="''${1:?Usage: solem-find pkg <name>}"
          ls /run/current-system/sw/bin/ 2>/dev/null | grep -i "$Q" | head -20
          ;;

        # ── SERVICE search (systemd) ──────────────────────────────────
        service|svc)
          Q="''${1:?Usage: solem-find service <pattern>}"
          systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | \
            grep -i "$Q" | head -20
          ;;

        # ── PROCESS search (ps) ───────────────────────────────────────
        process|proc|ps)
          Q="''${1:?Usage: solem-find process <name>}"
          ps aux | grep -i "$Q" | grep -v grep | head -10
          ;;

        # ── PORT search (ss) ──────────────────────────────────────────
        port)
          Q="''${1:?Usage: solem-find port <number or pattern>}"
          ss -tlnp 2>/dev/null | grep -i "$Q" | head -10
          ;;

        # ── HOME size summary ─────────────────────────────────────────
        home|size)
          du -sh "$HOME"/* 2>/dev/null | sort -h | tail -15
          ;;

        # ── INTERACTIVE picker (fzf) ──────────────────────────────────
        interactive|i)
          # Picker fzf su tutto in $HOME
          fd . "$HOME" 2>/dev/null | fzf --height 40% --reverse --preview 'head -50 {}'
          ;;

        # ── HELP ──────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-find — ricerca universale Spotlight-like (no GUI required)

  File:        solem-find file "*.pdf"
  Contenuto:   solem-find text "TODO" ~/notes
  Comandi:     solem-find cmd python
  Pacchetti:   solem-find pkg git
  Servizi:     solem-find service ssh
  Processi:    solem-find process firefox
  Porte:       solem-find port 8000
  Home size:   solem-find home
  Interactive: solem-find i                 (fzf picker)

Velocissimo. fd + ripgrep + fzf. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.quickSearch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-find` CLI ricerca universale (fd + rg + fzf)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      searchCli
      pkgs.fd
      pkgs.ripgrep
      pkgs.fzf
    ];
  };
}
