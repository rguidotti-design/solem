{ config, pkgs, lib, ... }:

# SOLEM JOURNAL SEALED — Step 12: systemd-journal FSS + log forwarding.
#
# Single responsibility: SOLO configurazione systemd-journald per produzione
# log tamper-evident via Forward Secure Sealing (FSS).
#
# Cosa fa FSS:
#   - Genera coppia sealing key (private + verify) al boot.
#   - Ogni N log entries (o ogni T secondi), un seal viene calcolato e
#     incatenato al precedente. La private key e' usata per generare il seal
#     e POI DISTRUTTA periodicamente (forward-secure).
#   - Un attaccante che modifica un log entry passato invalida tutta la
#     catena dal seal successivo → tampering DETECT.
#   - Verifica: `journalctl --verify`.
#
# Non sostituisce solem-net-audit (logga rete) o solem-ai-audit-strict
# (logga AI execve). E' a livello journal (TUTTI i log systemd).
#
# Tutto FOSS (systemd LGPL). 0 €.

let
  cfg = config.solem.journalSealed;
in {
  options.solem.journalSealed = {
    enable = lib.mkEnableOption "systemd-journal Forward Secure Sealing (FSS) tamper-evident";

    storage = lib.mkOption {
      type = lib.types.enum [ "persistent" "volatile" "auto" "none" ];
      default = "persistent";
      description = ''
        Dove conservare i log:
          - persistent: /var/log/journal (sopravvive reboot)
          - volatile: /run/log/journal (tmpfs, reset al reboot)
          - auto: persistent se /var/log/journal esiste
          - none: solo console (no log file)
      '';
    };

    maxRetentionSec = lib.mkOption {
      type = lib.types.str;
      default = "30day";
      description = "Quanti tempo tenere log prima di rotation";
    };

    systemMaxUse = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Limite max spazio disco per log";
    };

    sealIntervalSec = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = ''
        Ogni quanti secondi calcolare nuovo seal FSS.
        Default 10min = forward-secure window: un attacker che ottiene
        la machine DOPO il seal non puo' falsificare log piu' vecchi.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.journald = {
      # FSS: enabled tramite ExtraConfig
      extraConfig = ''
        # ── Storage + retention ──
        Storage=${cfg.storage}
        Compress=yes
        Seal=yes
        SplitMode=uid

        # ── Quota ──
        SystemMaxUse=${cfg.systemMaxUse}
        SystemKeepFree=500M
        MaxRetentionSec=${cfg.maxRetentionSec}
        MaxFileSec=1day

        # ── Forward-secure seal interval ──
        # systemd usa SyncIntervalSec per seal flush. Per FSS abilitato
        # tramite journalctl --setup-keys (manuale post-boot).
        SyncIntervalSec=${toString cfg.sealIntervalSec}

        # ── Rate limit per anti-flood (un servizio crazy non spamma) ──
        RateLimitIntervalSec=30s
        RateLimitBurst=10000

        # ── Forward to syslog (opt-in: facilita SIEM esterno) ──
        ForwardToSyslog=no
        ForwardToKMsg=no

        # ── Audit integration ──
        Audit=yes
      '';
    };

    # Setup FSS keys al primo boot
    systemd.services.solem-journal-fss-setup = {
      description = "SOLEM: setup FSS sealing keys per journald (one-shot)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "journal-fss-setup" ''
          set -eu
          KEYFILE=/var/lib/solem/journal-fss.key
          mkdir -p /var/lib/solem
          chmod 700 /var/lib/solem

          if [ -f "$KEYFILE" ]; then
            echo "FSS key gia' configurata: $KEYFILE"
            exit 0
          fi

          # journalctl --setup-keys genera la coppia + scrive la verify-key.
          # La output va salvata SU SUPPORTO ESTERNO (USB key, QR printout)
          # perche' senza non si puo' verify-mi successivamente.
          ${pkgs.systemd}/bin/journalctl --setup-keys --interval=${toString cfg.sealIntervalSec}s 2>&1 | \
            tee "$KEYFILE"
          chmod 600 "$KEYFILE"
          echo "FSS verify-key salvata in $KEYFILE — BACKUPPALA SU USB!"
        '';
      };
    };

    # CLI di ispezione
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-journal-verify";
        runtimeInputs = with pkgs; [ coreutils systemd ];
        text = ''
          ACTION="''${1:-verify}"

          case "$ACTION" in
            verify)
              echo "── SOLEM Journal Tamper Verify ──"
              echo "Esegue journalctl --verify su tutti i journal."
              echo "Se tampered: output mostra 'FAIL' su seal specifico."
              echo
              sudo journalctl --verify 2>&1 | tail -30
              ;;

            key)
              echo "── Verify key FSS (salva su USB!) ──"
              if [ -f /var/lib/solem/journal-fss.key ]; then
                sudo cat /var/lib/solem/journal-fss.key
              else
                echo "Nessuna FSS key. Run: systemctl restart solem-journal-fss-setup"
              fi
              ;;

            status)
              echo "── Journal status ──"
              sudo journalctl --disk-usage
              echo
              echo "── Storage path ──"
              ls -la /var/log/journal 2>/dev/null | head -10 || echo "(volatile)"
              echo
              echo "── FSS status ──"
              if [ -f /var/lib/solem/journal-fss.key ]; then
                echo "✓ FSS key presente in /var/lib/solem/journal-fss.key"
                echo "  Interval seal: ${toString cfg.sealIntervalSec}s"
              else
                echo "✗ FSS key NON configurata"
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-journal-verify — verifica tamper-evidence journal

  verify      journalctl --verify (controlla seal chain)
  key         mostra FSS verify-key (backup su USB!)
  status      disk usage + FSS configurato

Tamper detection: se un attaccante modifica un log entry passato,
la catena seal a partire dal sealing successivo viene invalidata.
Verify report: "PASS"=OK, "FAIL"=tampering rilevato.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/journal-sealed.md".text = ''
      # SOLEM Journal Sealed (FSS)

      ## Cosa fa

      systemd-journald configurato con Forward Secure Sealing:
        - Storage persistent in /var/log/journal/
        - Compress + Seal=yes
        - Sync interval ${toString cfg.sealIntervalSec}s
        - MaxFile 1day, MaxRetention ${cfg.maxRetentionSec}
        - SystemMaxUse ${cfg.systemMaxUse}

      Plus oneshot service `solem-journal-fss-setup` che genera coppia
      sealing key al primo boot.

      ## Threat coperto

      Un attaccante che ottiene root puo' MODIFICARE log entries esistenti
      in /var/log/journal/. Con FSS, ogni N secondi un sealing viene calcolato
      e la private-key precedente viene DISTRUTTA → un'attaccante POST-seal
      NON puo' falsificare entry PRE-seal (forward-secure).

      Verifica: `solem-journal-verify` esegue `journalctl --verify`.
      Output "PASS" = catena integra. "FAIL" = tampering rilevato.

      ## Setup post-installazione (CRITICO)

      ```bash
      solem-journal-verify key    # mostra verify-key
      # COPIA su USB esterno - chiave necessaria per verify futuro
      ```

      ## Limiti onesti

      - FSS NON protegge da deletion (un attaccante puo' rimuovere
        un file journal intero). Mitiga solo MODIFICATION.
      - La sealing key deve essere salvata SU SUPPORTO ESTERNO. Se rimane
        solo sul disco, attaccante root puo' rigenerare seal validi.
      - Performance: sealing ogni ${toString cfg.sealIntervalSec}s ha
        overhead minimo (<1% CPU su sistemi normali).
      - Recovery dopo tampering: i log corrotti restano tali. FSS DETECTa,
        non recupera contenuto.
    '';
  };
}
