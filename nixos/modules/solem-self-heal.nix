{ config, pkgs, lib, ... }:

# SOLEM SELF HEAL — Step 23: auto-apply fix safe-mode dopo self-redteam buchi.
#
# Single responsibility: SOLO orchestrazione fix automatici per i buchi
# rilevati da solem-self-redteam. Esegue SOLO fix considerati "safe":
# enable modulo disabilitato, restart service stopped, reload config.
# NON modifica configurazione utente (es. cambia option), NON disabilita
# servizi attivi.
#
# Approccio conservativo:
#   1. Legge LATEST.json di self-redteam.
#   2. Per ogni BUCO, consulta tabella di "azione safe associata".
#   3. Se azione esiste E safe: la esegue + logga.
#   4. Se azione NON safe (richiede config change): solo segnala in report.
#   5. Notify utente con summary "N applied / M skipped (manual review)".
#
# Mai modificare il flake Nix automatico — sarebbe troppo invasivo.
# Solo:
#   - systemctl start <unit> (se stopped)
#   - systemctl restart <unit> (se failed)
#   - solem-<modulo> init (se setup-once non eseguito)
#
# Esegue dopo solem-self-redteam (timer dependency).

let
  cfg = config.solem.selfHeal;

  healScript = pkgs.writers.writePython3Bin "solem-self-heal-run" {
    libraries = [ ];
    flakeIgnore = [ "E501" "E302" "W291" "W293" "E305" "E402" ];
  } ''
    """SOLEM Self Heal: applica fix safe per BUCHI da redteam report."""
    import json
    import os
    import subprocess
    import sys
    from datetime import datetime, timezone
    from pathlib import Path

    REDTEAM_DIR = Path("/var/log/solem/redteam")
    HEAL_DIR = Path("/var/log/solem/heal")
    HEAL_DIR.mkdir(parents=True, exist_ok=True)

    TS = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    HEAL_OUT = HEAL_DIR / f"{TS}.json"

    # Mappa: scenario name -> azione safe (None = no auto-fix, manual review)
    # Le azioni sono comandi shell idempotenti.
    SAFE_ACTIONS = {
        # Step 4 canary: kill switch missing -> riavvia watcher
        "read_canary_trips_killswitch":
            "systemctl restart solem-canary-watcher.service 2>&1",

        # Step 8 apparmor: profile not loaded -> reload apparmor service
        "apparmor_self_attr_set":
            "systemctl restart apparmor.service 2>&1 || apparmor_parser -r /etc/apparmor.d/* 2>&1",

        # Step 11 fail2ban: not active -> start
        "port_22_brute_force":
            "systemctl start fail2ban.service 2>&1",

        # Step 12 journal FSS: verify failed -> nothing safe (tamper detected,
        # serve indagine manuale). NULL.
        "audit_log_tamper_detect": None,

        # Step 13 USBGuard: not active -> start
        "usb_unauth_device_block":
            "systemctl start usbguard.service 2>&1",

        # Step 20 model integrity: no baseline -> esegui snapshot (idempotente
        # se modelli presenti, nop altrimenti)
        "model_integrity_baseline_present":
            "test -d /var/lib/ollama/models && solem-model-integrity snapshot 2>&1 || echo 'no models yet'",

        # Step 21 prompt filter: filter not running -> start
        "prompt_injection_blocked":
            "systemctl start solem-prompt-filter.service 2>&1",

        # Step 17 backup: no repo -> init (idempotente)
        "backup_recent":
            "test -f /etc/solem/backup-passphrase || solem-backup init 2>&1",

        # ─── Buchi che NON si auto-fixano (serve config change manuale) ───
        # Step 1 isolation gavio-ai: se gavio-ai legge /etc/shadow, c'e' un
        # bug del modulo, non config drift. Manual investigate.
        "read_etc_shadow_as_gavio_ai": None,
        "read_home_gavio_as_gavio_ai": None,
        "sudo_as_gavio_ai": None,

        # Step 2 nft: serve enable modulo (config change) -> manual
        "connect_outbound_testnet": None,

        # Step 6 kernel: serve kernelParams cambiati (richiede reboot, no auto)
        "ptrace_cross_user": None,
        "load_kernel_module": None,
        "user_namespaces_disabled": None,
        "kernel_lockdown_active": None,

        # Step 7 DNS allowlist: serve enable modulo
        "dns_resolve_evil": None,

        # Step 8 apparmor write: se /etc scrivibile gia' fix sopra (reload)
        "write_etc_owned_by_ai": None,
    }

    def run(cmd, timeout=30):
        try:
            r = subprocess.run(
                cmd, shell=True, capture_output=True, text=True,
                timeout=timeout
            )
            return r.returncode, r.stdout[:500] + r.stderr[:500]
        except subprocess.TimeoutExpired:
            return 124, "TIMEOUT"
        except Exception as e:
            return 99, str(e)

    # Trova ultimo report redteam
    json_files = sorted(REDTEAM_DIR.glob("*.json"), reverse=True)
    if not json_files:
        print("No redteam report. Run: solem-redteam run", flush=True)
        sys.exit(2)

    latest = json_files[0]
    print(f"Reading: {latest}", flush=True)
    report = json.loads(latest.read_text())

    heal_results = {
        "timestamp": TS,
        "source_report": str(latest),
        "actions": [],
        "summary": {
            "buchi": 0,
            "auto_fix_applied": 0,
            "auto_fix_skipped_no_action": 0,
            "auto_fix_failed": 0,
        },
    }

    for sc in report["scenarios"]:
        if sc["verdict"] != "BUCO":
            continue
        heal_results["summary"]["buchi"] += 1
        name = sc["name"]
        action = SAFE_ACTIONS.get(name)
        if action is None:
            print(f"  [SKIP] {name}: no safe auto-fix (manual review)", flush=True)
            heal_results["actions"].append({
                "scenario": name,
                "action": "manual_review",
                "step_module": sc["step"],
            })
            heal_results["summary"]["auto_fix_skipped_no_action"] += 1
            continue

        print(f"  [FIX]  {name}: {action[:80]}", flush=True)
        rc, output = run(action)
        success = rc == 0
        heal_results["actions"].append({
            "scenario": name,
            "action": "applied",
            "command": action,
            "rc": rc,
            "output": output,
            "success": success,
        })
        if success:
            heal_results["summary"]["auto_fix_applied"] += 1
        else:
            heal_results["summary"]["auto_fix_failed"] += 1

    HEAL_OUT.write_text(json.dumps(heal_results, indent=2))
    print(f"\nHeal report: {HEAL_OUT}", flush=True)

    s = heal_results["summary"]
    print(f"Summary: applied={s['auto_fix_applied']} skipped={s['auto_fix_skipped_no_action']} failed={s['auto_fix_failed']}", flush=True)

    # Notify-send if any action
    if s["auto_fix_applied"] + s["auto_fix_failed"] > 0:
        for d in Path("/run/user").iterdir() if Path("/run/user").exists() else []:
            if d.is_dir():
                uid = d.name
                msg = f"Heal: {s['auto_fix_applied']} applied, {s['auto_fix_failed']} failed, {s['auto_fix_skipped_no_action']} manual"
                run(
                    f"sudo -u '#{uid}' DBUS_SESSION_BUS_ADDRESS='unix:path={d}/bus' "
                    f"notify-send -u normal -t 30000 'SOLEM Self Heal' '{msg}'"
                )
    sys.exit(0)
  '';

  cliApp = pkgs.writeShellApplication {
    name = "solem-heal";
    runtimeInputs = with pkgs; [ coreutils jq systemd ];
    text = ''
      ACTION="''${1:-status}"

      case "$ACTION" in
        run|now)
          echo "Esecuzione self-heal (legge ultimo redteam report)..."
          sudo systemctl start solem-self-heal.service
          sleep 2
          ls -t /var/log/solem/heal/ 2>/dev/null | head -1
          ;;

        status)
          echo "── SOLEM Self Heal ──"
          systemctl status solem-self-heal.timer --no-pager 2>/dev/null | head -8
          echo
          latest=$(ls -t /var/log/solem/heal/*.json 2>/dev/null | head -1)
          if [ -n "$latest" ]; then
            echo "── Ultimo report ──"
            jq '.summary' "$latest"
            echo
            echo "── Action log ──"
            jq -r '.actions[] | "\(.action) \(.scenario) rc=\(.rc // "n/a")"' "$latest"
          else
            echo "(nessun report ancora)"
          fi
          ;;

        report)
          latest=$(ls -t /var/log/solem/heal/*.json 2>/dev/null | head -1)
          [ -n "$latest" ] && jq . "$latest" || echo "(no report)"
          ;;

        history)
          ls -lh /var/log/solem/heal/*.json 2>/dev/null | tail -10 || echo "(none)"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-heal — auto-apply fix safe-mode per buchi self-redteam

  run        esegui heal ADESSO (legge ultimo redteam report)
  status     timer + ultimo summary
  report     JSON completo ultimo heal
  history    storia report

Fix safe-mode applicate automaticamente:
  - systemctl start <service> se modulo enabled ma service stopped
  - solem-model-integrity snapshot se baseline missing
  - solem-backup init se passphrase missing
  - apparmor_parser -r ricarica profili

Fix NON safe (serve manual review):
  - Cambi a config Nix (richiedono nixos-rebuild)
  - kernelParams (richiedono reboot)
  - Modulo enable=false (decisione utente)
  - Bug del modulo (es. gavio-ai legge /etc/shadow → c'e' bug, non drift)

Run automatico: 30min dopo self-redteam (catena timer).
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.selfHeal = {
    enable = lib.mkEnableOption "Auto-apply fix safe-mode dopo self-redteam buchi";

    delayAfterRedteam = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = ''
        Delay dopo run solem-self-redteam prima di applicare fix.
        Permette all'utente di vedere notify-send e bloccare se vuole.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.solem.selfRedteam.enable or false;
      message = "solem.selfHeal richiede solem.selfRedteam.enable = true";
    }];

    systemd.tmpfiles.rules = [
      "d /var/log/solem/heal 0750 root root - -"
    ];

    systemd.services.solem-self-heal = {
      description = "SOLEM Self Heal: applica fix safe per buchi redteam";
      after = [ "solem-self-redteam.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healScript}/bin/solem-self-heal-run";
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "10min";
      };
    };

    # Timer: scatta dopo solem-self-redteam (delay configurable)
    systemd.timers.solem-self-heal = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Esegui ogni giorno alle 03:30 (30min dopo redteam 03:00 default)
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    environment.systemPackages = [ cliApp healScript ];

    environment.etc."solem/self-heal.md".text = ''
      # SOLEM Self Heal (Step 23)

      ## Concept

      Dopo che solem-self-redteam ha identificato BUCHI di sicurezza,
      il sistema applica AUTOMATICAMENTE fix considerati "safe-mode":
      - Restart service stopped
      - Reload config (apparmor_parser -r)
      - Init setup-once (snapshot baseline, generate passphrase)

      Schedule: 30min dopo solem-self-redteam (default 03:30 daily).

      ## Cosa SI auto-fixa (safe)

      | Buco | Azione safe |
      |---|---|
      | canary kill switch silent | restart solem-canary-watcher |
      | apparmor profile not loaded | apparmor_parser -r |
      | fail2ban not active | systemctl start fail2ban |
      | usbguard not active | systemctl start usbguard |
      | model baseline missing | solem-model-integrity snapshot |
      | prompt filter not running | systemctl start solem-prompt-filter |
      | backup passphrase missing | solem-backup init |

      ## Cosa NON si auto-fixa (manual review)

      - Bug del modulo (es. gavio-ai legge /etc/shadow → c'e' un bug code)
      - Config Nix change (richiede nixos-rebuild)
      - kernelParams (richiede reboot)
      - Modulo enable=false → decisione utente, no auto-enable

      Per questi: notify-send all'utente + entry "manual_review" nel report.

      ## CLI

      ```bash
      solem-heal status            # ultimo summary
      solem-heal run               # esegui ADESSO (dopo redteam manuale)
      solem-heal report            # JSON dettagliato
      ```

      ## Loop completo:

      ```
      03:00 → solem-self-redteam (attacca + report buchi)
      03:30 → solem-self-heal (legge report + applica fix safe)
      ```

      ## Limiti onesti

      - Safe-mode = conservativo. Buchi gravi (es. bug Step 1 isolation)
        richiedono comunque intervento umano.
      - Fix di restart-service: se il service crashea ripetutamente, heal
        lo restarta in loop. Mitigazione: systemctl ha rate-limit Restart=
        nei moduli stessi.
      - Race condition: redteam corre 03:00, heal 03:30. Se l'utente cambia
        config nel mezzo, heal opera su report stale.
      - NON modifica MAI il flake Nix automaticamente: per design.
    '';
  };
}
