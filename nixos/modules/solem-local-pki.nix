{ config, pkgs, lib, ... }:

# SOLEM LOCAL PKI — Step 26: Certificate Authority interna + mTLS.
#
# Single responsibility: SOLO gestione CA root + emissione cert per
# servizi interni SOLEM (GAVIO API, ollama, prompt-filter, ...).
# Tutto via age/step-ca FOSS.
#
# Threat coperto:
#   - Intercept comunicazione tra servizi interni SOLEM (ollama ↔ GAVIO ↔
#     filter ↔ nginx). Senza mTLS, attacker locale puo' sniffare loopback
#     se ha qualche capability (es. cgroup access).
#   - Service masquerading: un processo malicious finge di essere GAVIO
#     e accetta richieste. Con mTLS: serve cert firmato dalla CA SOLEM.
#   - DNS spoofing su .solem.local (localhost): senza pinning cert, un
#     attacker dirotta il nome. Con CA SOLEM + cert pinning, fail.
#
# Stack:
#   - step-ca (Smallstep, Apache-2.0): CA software-only, no HSM richiesto
#   - mTLS: client cert + server cert mutual auth
#   - Cert auto-renewal via step-ca server-side
#
# Tutto FOSS, 0 €.

let
  cfg = config.solem.localPki;

  caDir = "/var/lib/solem/pki";

  caCli = pkgs.writeShellApplication {
    name = "solem-pki";
    runtimeInputs = with pkgs; [ coreutils step-cli step-ca openssl ];
    text = ''
      ACTION="''${1:-status}"
      shift || true
      CADIR="${caDir}"
      ORG="${cfg.organization}"

      case "$ACTION" in
        init)
          if [ -d "$CADIR" ] && [ -f "$CADIR/secrets/root_ca_key" ]; then
            echo "CA gia' inizializzata in $CADIR"
            exit 0
          fi
          echo "── Inizializzo SOLEM CA in $CADIR ──"
          sudo mkdir -p "$CADIR"
          sudo chmod 700 "$CADIR"

          # Genera password root + intermediate
          ROOT_PW=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 40)
          INT_PW=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 40)

          # Salva password (chmod 600)
          echo "$ROOT_PW" | sudo tee "$CADIR/root.pw" > /dev/null
          echo "$INT_PW" | sudo tee "$CADIR/int.pw" > /dev/null
          sudo chmod 600 "$CADIR/root.pw" "$CADIR/int.pw"

          # Init CA con step-ca
          sudo env STEPPATH="$CADIR" step ca init \
            --name "SOLEM Root CA" \
            --dns "ca.solem.local,localhost" \
            --address ":8443" \
            --provisioner "solem-admin" \
            --provisioner-password-file "$CADIR/root.pw" \
            --password-file "$CADIR/int.pw" \
            --deployment-type standalone 2>&1 | tail -20

          echo
          echo "✓ CA inizializzata. Password salvate in $CADIR/{root,int}.pw"
          echo "  BACKUP CRITICO: copia $CADIR su USB esterno!"
          ;;

        status)
          echo "── SOLEM Local PKI ──"
          echo "Org: $ORG"
          echo "CA dir: $CADIR"
          if [ -d "$CADIR/certs" ]; then
            echo
            echo "── Cert emessi ──"
            sudo ls -la "$CADIR/certs/" 2>/dev/null | tail -20
          else
            echo "(CA non inizializzata. Run: solem-pki init)"
          fi
          ;;

        issue)
          # Emetti cert per un servizio
          NAME="''${1:?Usage: solem-pki issue <service-name> [SAN1,SAN2,...]}"
          SANS="''${2:-$NAME.solem.local,localhost,127.0.0.1}"
          OUT_DIR="/var/lib/solem/pki/certs/$NAME"
          sudo mkdir -p "$OUT_DIR"

          sudo env STEPPATH="$CADIR" step ca certificate \
            --provisioner "solem-admin" \
            --provisioner-password-file "$CADIR/root.pw" \
            "$NAME" \
            "$OUT_DIR/cert.pem" \
            "$OUT_DIR/key.pem" \
            --san "$SANS" \
            --not-after 8760h \
            --force
          sudo chmod 644 "$OUT_DIR/cert.pem"
          sudo chmod 600 "$OUT_DIR/key.pem"
          echo "✓ Cert emesso: $OUT_DIR/cert.pem (1 anno)"
          echo "  Key: $OUT_DIR/key.pem (chmod 600)"
          echo "  SANs: $SANS"
          ;;

        renew)
          NAME="''${1:?Usage: solem-pki renew <service-name>}"
          OUT_DIR="$CADIR/certs/$NAME"
          if [ ! -f "$OUT_DIR/cert.pem" ]; then
            echo "Cert non trovato: $OUT_DIR/cert.pem"
            exit 1
          fi
          sudo env STEPPATH="$CADIR" step ca renew \
            "$OUT_DIR/cert.pem" "$OUT_DIR/key.pem" \
            --force
          echo "✓ Cert renewed"
          ;;

        list)
          if [ -d "$CADIR/certs" ]; then
            for d in "$CADIR"/certs/*/; do
              [ -d "$d" ] || continue
              NAME=$(basename "$d")
              EXP=$(openssl x509 -in "$d/cert.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
              echo "  $NAME → expires $EXP"
            done
          else
            echo "(nessun cert)"
          fi
          ;;

        ca-cert|root)
          if [ -f "$CADIR/certs/root_ca.crt" ]; then
            cat "$CADIR/certs/root_ca.crt"
          else
            echo "CA non inizializzata"
            exit 1
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-pki — Local Certificate Authority + mTLS

  init                   inizializza CA root + intermediate (PRIMO setup)
  status                 stato CA + cert emessi
  issue <name> [SANs]    emetti cert per servizio (1 anno)
  renew <name>           rinnova cert
  list                   elenca tutti i cert + expiry
  ca-cert                stampa root CA cert (per pinning client)

Threat coperto:
  - Intercept comunicazione inter-service (ollama ↔ GAVIO ↔ filter)
  - Service masquerading (processo malicious finge di essere GAVIO)
  - DNS spoofing su .solem.local

Workflow primo setup:
  1. solem-pki init                       (genera CA root + intermediate)
  2. solem-pki issue gavio-api            (cert per nginx + GAVIO API)
  3. solem-pki issue ollama               (cert per ollama service)
  4. Configura servizi per usare cert (TLS mutual auth)
  5. BACKUP /var/lib/solem/pki su USB esterno

Cert auto-renewal: futuro Step (systemd timer pre-expiry).
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.localPki = {
    enable = lib.mkEnableOption "Local PKI Certificate Authority + mTLS";

    organization = lib.mkOption {
      type = lib.types.str;
      default = "SOLEM";
      description = "Org name nei certificati emessi";
    };

    autoIssueServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "gavio-api" "ollama" "solem-prompt-filter" ];
      description = ''
        Lista servizi per cui emettere cert automaticamente al boot.
        Cert da 1 anno, auto-renew via systemd timer.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${caDir} 0700 root root - -"
      "d ${caDir}/certs 0755 root root - -"
    ];

    environment.systemPackages = with pkgs; [
      step-cli
      step-ca
      caCli
    ];

    # Auto-init CA al primo boot
    systemd.services.solem-pki-init = {
      description = "SOLEM: init local PKI CA at first boot";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "solem-pki-init" ''
          if [ ! -f ${caDir}/secrets/root_ca_key ]; then
            ${caCli}/bin/solem-pki init
          fi
          # Auto-emit cert per i servizi configurati
          ${lib.concatMapStringsSep "\n" (svc: ''
            if [ ! -f ${caDir}/certs/${svc}/cert.pem ]; then
              ${caCli}/bin/solem-pki issue ${svc}
            fi
          '') cfg.autoIssueServices}
        '';
      };
    };

    # Cert auto-renew (90 giorni prima di expiry)
    systemd.services.solem-pki-renew = {
      description = "SOLEM: auto-renew cert in scadenza < 90gg";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "solem-pki-renew" ''
          set +e
          for cert_dir in ${caDir}/certs/*/; do
            [ -d "$cert_dir" ] || continue
            NAME=$(basename "$cert_dir")
            # Skip root_ca dir
            [ "$NAME" = "root_ca.crt" ] && continue
            [ ! -f "$cert_dir/cert.pem" ] && continue
            # Check expiry
            EXPIRY=$(${pkgs.openssl}/bin/openssl x509 -in "$cert_dir/cert.pem" -noout -enddate | sed 's/notAfter=//')
            EXPIRY_TS=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
            NOW_TS=$(date +%s)
            DAYS_LEFT=$(( (EXPIRY_TS - NOW_TS) / 86400 ))
            if [ "$DAYS_LEFT" -lt 90 ] && [ "$DAYS_LEFT" -gt 0 ]; then
              echo "Renewing $NAME (expires in $DAYS_LEFT days)"
              ${caCli}/bin/solem-pki renew "$NAME" || true
            fi
          done
        '';
      };
    };

    systemd.timers.solem-pki-renew = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    environment.etc."solem/local-pki.md".text = ''
      # SOLEM Local PKI (Step 26)

      Certificate Authority interna per emettere cert ai servizi SOLEM
      (GAVIO API, ollama, prompt-filter, ecc.) + mTLS mutual auth.

      ## Stack
      - **step-ca** (Smallstep, Apache-2.0): CA software-only, no HSM
      - **step-cli** (Apache-2.0): client per issuance/renewal
      - mTLS: server cert + client cert mutual verification

      ## Setup primo uso

      ```bash
      sudo solem-pki init                    # genera CA root + int
      sudo solem-pki issue gavio-api         # cert per nginx/GAVIO
      sudo solem-pki issue ollama            # cert per ollama
      sudo solem-pki issue prompt-filter

      # Configura servizi:
      # nginx: ssl_certificate /var/lib/solem/pki/certs/gavio-api/cert.pem;
      # ollama: TLS_CERT=/var/lib/solem/pki/certs/ollama/cert.pem
      ```

      ## Auto-renew
      systemd timer weekly: renew cert con expiry < 90 giorni.

      ## Auto-issue al boot
      ```nix
      solem.localPki.autoIssueServices = [ "gavio-api" "ollama" ];
      ```

      ## Threat coperto
      - **Intercept inter-service**: senza mTLS, processo malicious con
        cgroup access puo' sniffare loopback. Con mTLS cert pinning:
        impossible senza CA private key.
      - **Service masquerading**: processo malicious finge di essere
        GAVIO. Cert verify fail → connessione rifiutata.
      - **DNS spoofing .solem.local**: con pin CA, fail anche se
        attacker controlla resolver.

      ## Limiti onesti
      - CA private key on disk (/var/lib/solem/pki/secrets/). Se rubata,
        attacker emette cert validi. BACKUP USB esterno + offsite essenziale.
      - Step-ca standalone (no HSM): cert signing in software. Per max
        security paranoia, usare YubiHSM (hardware).
      - mTLS richiede config esplicita per ogni servizio (no auto-magia).
      - Auto-renew settimanale: cert con < 90gg expiry. Default 1 anno.
    '';
  };
}
