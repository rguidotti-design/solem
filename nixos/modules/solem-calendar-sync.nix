{ config, pkgs, lib, ... }:

# SOLEM CALENDAR SYNC — sync Google Calendar / Outlook / iCloud via CalDAV.
#
# Single responsibility: SOLO CLI helper per khal (CalDAV CLI FOSS) +
# vdirsyncer (FOSS sync engine).
#
# Pattern: Radicale locale + vdirsyncer pull/push verso CalDAV remoti.
# Mantieni privacy: i dati restano locali, sync è esplicito.

let
  cfg = config.solem.calendarSync;

  calCli = pkgs.writeShellApplication {
    name = "solem-cal";
    runtimeInputs = with pkgs; [ coreutils khal vdirsyncer ];
    text = ''
      ACTION="''${1:-list}"
      shift || true

      case "$ACTION" in
        # ── khal CLI ─────────────────────────────────────────────────
        list|ls|today)
          khal list today 2>/dev/null || echo "(khal non configurato; vedi: solem-cal init)"
          ;;
        week)
          khal calendar "$(date -d 'today' +%Y-%m-%d)" "$(date -d '+7 days' +%Y-%m-%d)"
          ;;
        add)
          khal new "$@"
          ;;
        edit)
          khal edit "$@"
          ;;
        # ── Sync ─────────────────────────────────────────────────────
        sync)
          vdirsyncer sync
          ;;
        discover)
          vdirsyncer discover
          ;;
        # ── Setup primo uso ──────────────────────────────────────────
        init)
          mkdir -p "$HOME/.vdirsyncer" "$HOME/.config/khal"
          if [ ! -f "$HOME/.vdirsyncer/config" ]; then
            cat > "$HOME/.vdirsyncer/config" <<'EOF'
[general]
status_path = "~/.vdirsyncer/status/"

# Locale Radicale (se solem-personal-cloud attivo)
[storage local]
type = "filesystem"
path = "~/.calendars/"
fileext = ".ics"

# Esempio: Google Calendar (configurare auth)
# [storage google]
# type = "google_calendar"
# token_file = "~/.vdirsyncer/google.token"
# client_id = "your-client-id"
# client_secret = "your-secret"

# [pair google_local]
# a = "google"
# b = "local"
# collections = ["from a", "from b"]
# conflict_resolution = "a wins"
EOF
            echo "vdirsyncer config creato in ~/.vdirsyncer/config"
            echo "Modifica per aggiungere Google/Outlook/iCloud, poi:"
            echo "  vdirsyncer discover"
            echo "  vdirsyncer sync"
          else
            echo "Config già esistente: ~/.vdirsyncer/config"
          fi
          ;;
        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-cal — calendar CalDAV CLI (khal + vdirsyncer FOSS)

  list / today         eventi oggi
  week                 prossimi 7 giorni
  add "summary"        crea evento (interactive)
  edit                 modifica evento

  Sync:
    init               crea config vdirsyncer template
    discover           scopri collezioni CalDAV remote
    sync               pull/push

Provider supportati (config in ~/.vdirsyncer/config):
  - Google Calendar
  - Outlook.com / Office 365
  - iCloud (richiede app password)
  - Nextcloud (CalDAV)
  - Radicale (self-host FOSS — preferito)

Privacy: dati locali in ~/.calendars/ (ICS files).
Sync esplicito on-demand. Niente account terzo richiesto se usi Radicale.

Tutto FOSS. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.calendarSync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-cal` khal + vdirsyncer (CalDAV CLI)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      calCli
      khal
      vdirsyncer
    ];
  };
}
