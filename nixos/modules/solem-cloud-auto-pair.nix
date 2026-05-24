{ config, pkgs, lib, ... }:

# SOLEM CLOUD AUTO-PAIR — onboarding cloud personale 1-click.
#
# Single responsibility: SOLO CLI `solem-cloud setup` che:
#   1. Avvia Nextcloud server locale (Docker/Podman o systemd)
#   2. Genera credenziali iniziali
#   3. Setup client desktop sync su $HOME
#   4. Mostra QR code per pairing smartphone (Nextcloud app)
#
# Tutto FOSS. 0 €. Tutto locale.

let
  cfg = config.solem.cloudAutoPair;

  cloudCli = pkgs.writeShellApplication {
    name = "solem-cloud";
    runtimeInputs = with pkgs; [ coreutils curl jq qrencode ];
    text = ''
      ACTION="''${1:-help}"

      STATE_DIR="$HOME/.local/state/solem-cloud"
      mkdir -p "$STATE_DIR"
      CRED_FILE="$STATE_DIR/credentials.json"

      case "$ACTION" in

        # ── Setup iniziale ─────────────────────────────────────────────
        setup|init)
          # Verifica se Nextcloud è attivo
          if curl -s -m 2 -o /dev/null http://127.0.0.1:80/index.php/login 2>/dev/null; then
            echo "✓ Nextcloud locale già attivo"
          else
            echo "Nextcloud non attivo. Per avviarlo:"
            echo "  Opzione 1: solem.cloudPersonal.enable = true; (richiede reboot)"
            echo "  Opzione 2: Docker rapido:"
            echo "    docker run -d -p 80:80 -v nextcloud:/var/www/html nextcloud:latest"
            echo
            exit 1
          fi

          # Genera credenziali random
          if [ ! -f "$CRED_FILE" ]; then
            ADMIN_USER="solem-$(date +%s | tail -c 5)"
            ADMIN_PASS=$(head -c 24 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=')
            cat > "$CRED_FILE" <<EOF
{"user":"$ADMIN_USER","pass":"$ADMIN_PASS","url":"http://$(hostname):80"}
EOF
            chmod 600 "$CRED_FILE"
            echo "Credenziali generate:"
            cat "$CRED_FILE" | jq
          else
            echo "Credenziali esistenti:"
            cat "$CRED_FILE" | jq
          fi
          ;;

        # ── Mostra QR code per pairing smartphone ────────────────────
        qr|pair)
          if [ ! -f "$CRED_FILE" ]; then
            echo "ERRORE: esegui prima 'solem-cloud setup'"
            exit 1
          fi
          URL=$(jq -r '.url' "$CRED_FILE")
          USER=$(jq -r '.user' "$CRED_FILE")
          PASS=$(jq -r '.pass' "$CRED_FILE")
          # Format Nextcloud iOS/Android app: nc://login/user:USER&password:PASS&server:URL
          NC_URL="nc://login/user:$USER&password:$PASS&server:$URL"
          echo "Scansiona con Nextcloud app iOS/Android:"
          echo
          echo "$NC_URL" | qrencode -t UTF8
          echo
          echo "Oppure: vai nell'app → Add Account → URL: $URL"
          ;;

        # ── Status sync ──────────────────────────────────────────────
        status)
          if [ -f "$CRED_FILE" ]; then
            echo "── Credenziali SOLEM cloud ──"
            cat "$CRED_FILE" | jq
            echo
            URL=$(jq -r '.url' "$CRED_FILE")
            if curl -s -m 2 -o /dev/null "$URL"; then
              echo "✓ Nextcloud online"
            else
              echo "✗ Nextcloud offline ($URL non risponde)"
            fi
          else
            echo "Non configurato. Esegui: solem-cloud setup"
          fi
          ;;

        # ── Avvia Nextcloud Desktop sync client ─────────────────────
        desktop-client|client)
          if ! command -v nextcloud >/dev/null 2>&1; then
            echo "Installa Nextcloud Desktop client:"
            echo "  solem-app install nextcloud"
            echo "  (oppure: flatpak install flathub com.nextcloud.desktopclient.nextcloud)"
            exit 1
          fi
          nextcloud &
          echo "Nextcloud Desktop avviato. Inserisci credenziali da:"
          jq '.' "$CRED_FILE"
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-cloud — cloud personale auto-pair (Nextcloud FOSS)

  solem-cloud setup           inizializza credenziali
  solem-cloud qr              QR code pairing smartphone
  solem-cloud status          stato server + credenziali
  solem-cloud client          avvia Nextcloud Desktop sync

Step usuale (3 step):
  1. solem.cloudPersonal.enable = true        # in configuration.nix, una tantum
  2. solem-cloud setup                        # genera credenziali
  3. solem-cloud qr                           # scansiona col telefono

Funziona offline (rete LAN). Server Nextcloud va su :80.
Pairing client: scansiona QR o vai in Nextcloud app → URL.

Tutto FOSS. 0 €. Nessun account terzo.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.cloudAutoPair = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-cloud` CLI auto-pair Nextcloud";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cloudCli
      pkgs.qrencode
    ];
  };
}
