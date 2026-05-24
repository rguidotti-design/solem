{ config, pkgs, lib, ... }:

# SOLEM PRODUCTIVITY — CLI minimal per pomodoro + todo + note.
#
# Single responsibility: SOLO 3 mini-tool produttività shell-based.
# Niente daemon, niente DB. Solo file plain text in ~/.local/share/solem/.
#
# Tutto FOSS, 0 €.

let
  cfg = config.solem.productivity;

  pomoCli = pkgs.writeShellApplication {
    name = "solem-pomo";
    runtimeInputs = with pkgs; [ coreutils libnotify ];
    text = ''
      MINS="''${1:-25}"
      LABEL="''${2:-Pomodoro}"
      echo "🍅 $LABEL — $MINS minuti. Inizio: $(date +%H:%M)"
      SEC=$((MINS * 60))
      sleep "$SEC"
      echo "⏰ TIME! $LABEL completato"
      if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "Pomodoro" "$LABEL completato ($MINS min)"
      fi
      # Sound bell
      printf "\a\a\a"
    '';
  };

  todoCli = pkgs.writeShellApplication {
    name = "solem-todo";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      STORE="$HOME/.local/share/solem/todo.txt"
      mkdir -p "$(dirname "$STORE")"
      touch "$STORE"

      ACTION="''${1:-list}"
      shift || true

      case "$ACTION" in
        add|a)
          TXT="''${*:?Usage: solem-todo add <text>}"
          ID=$(($(wc -l < "$STORE") + 1))
          echo "$ID|[ ] $TXT|$(date -Iseconds)" >> "$STORE"
          echo "✓ Aggiunto #$ID: $TXT"
          ;;
        list|ls|l|"")
          if [ ! -s "$STORE" ]; then
            echo "(nessun task)"
          else
            awk -F'|' '{printf "%3s  %s\n", $1, $2}' "$STORE"
          fi
          ;;
        done|d)
          ID="''${1:?Usage: solem-todo done <id>}"
          sed -i "s/^$ID|\[ \]/$ID|[x]/" "$STORE"
          echo "✓ Done #$ID"
          ;;
        rm|del)
          ID="''${1:?Usage: solem-todo rm <id>}"
          sed -i "/^$ID|/d" "$STORE"
          echo "✓ Rimosso #$ID"
          ;;
        clear)
          : > "$STORE"
          echo "✓ Tutti i task cancellati"
          ;;
        export)
          cat "$STORE"
          ;;
        *)
          echo "solem-todo — CLI task list (plain text)"
          echo "  solem-todo add <text>     aggiungi"
          echo "  solem-todo list           lista"
          echo "  solem-todo done <id>      segna come fatto"
          echo "  solem-todo rm <id>        rimuovi"
          echo "  solem-todo clear          cancella tutti"
          echo "  Store: $STORE"
          ;;
      esac
    '';
  };

  noteCli = pkgs.writeShellApplication {
    name = "solem-note";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      DIR="$HOME/.local/share/solem/notes"
      mkdir -p "$DIR"

      ACTION="''${1:-list}"
      shift || true

      case "$ACTION" in
        add|new|n)
          TITLE="''${*:?Usage: solem-note add <title>}"
          SAFE=$(echo "$TITLE" | tr ' ' '_' | tr -cd '[:alnum:]._-')
          FILE="$DIR/$(date +%Y%m%d-%H%M)-$SAFE.md"
          echo "# $TITLE" > "$FILE"
          echo >> "$FILE"
          echo "Created: $(date -Iseconds)" >> "$FILE"
          echo >> "$FILE"
          "''${EDITOR:-vi}" "$FILE"
          echo "Salvato: $FILE"
          ;;
        list|ls|l|"")
          ls -lt "$DIR" 2>/dev/null | tail -n +2 | head -20
          ;;
        search|s|grep)
          Q="''${1:?Usage: solem-note search <pattern>}"
          grep -l -i "$Q" "$DIR"/*.md 2>/dev/null || echo "(nessun match)"
          ;;
        cat|show)
          NAME="''${1:?Usage: solem-note show <filename>}"
          cat "$DIR/$NAME" 2>/dev/null || ls "$DIR" | grep "$NAME" | head -5
          ;;
        *)
          echo "solem-note — CLI note markdown"
          echo "  solem-note add <title>    nuova nota (apre $EDITOR)"
          echo "  solem-note list           ultime 20"
          echo "  solem-note search <q>     ricerca contenuto"
          echo "  solem-note show <file>    visualizza"
          echo "  Store: $DIR/"
          ;;
      esac
    '';
  };
in {
  options.solem.productivity = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa 3 mini-CLI produttività: solem-pomo, solem-todo, solem-note";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pomoCli
      todoCli
      noteCli
    ];
  };
}
