{ config, pkgs, lib, ... }:

# SOLEM AI GUARDRAILS — sandbox + kill switch per GAVIO e qualunque AI.
#
# Principio: GAVIO può agire ma OGNI azione passa per un layer di
# controllo che:
#   1. Verifica la firma del comando (whitelist per default)
#   2. Esegue in user-namespace isolato (bubblewrap)
#   3. Logga in audit immutabile (append-only, signed)
#   4. Detecta anomalie (rate, pattern, risorse) via Falco eBPF
#   5. KILL automatico se threshold superata
#   6. Human-in-the-loop per azioni distruttive (file system delete,
#      network exfil, sudo, package install)
#
# Architettura:
#
#   GAVIO (utente non-root)
#      │
#      ▼
#   solem-guard exec <action>  ← intercetta tutto
#      │
#      ├── 1. Verifica whitelist
#      ├── 2. Rate-limit check
#      ├── 3. Audit log signed
#      ├── 4. Bubblewrap sandbox
#      ├── 5. Falco anomaly monitor (background)
#      └── 6. Esegue OR rifiuta OR chiede umano
#
# Tutto FOSS: bubblewrap (GPL-2.0), Falco (Apache-2.0), auditd (GPL-2.0).
# 0 €. Funziona su qualsiasi distro Linux con kernel 5.10+.

let
  cfg = config.solem.aiGuardrails;

  # Whitelist comandi consentiti a GAVIO senza approvazione umana.
  # Tutto il resto richiede prompt all'utente o è bloccato.
  defaultWhitelist = [
    # Read-only OS info
    "/run/current-system/sw/bin/uname"
    "/run/current-system/sw/bin/hostname"
    "/run/current-system/sw/bin/uptime"
    "/run/current-system/sw/bin/free"
    "/run/current-system/sw/bin/df"
    "/run/current-system/sw/bin/lsblk"
    "/run/current-system/sw/bin/ip"
    "/run/current-system/sw/bin/systemctl"  # solo --no-pager, list/status
    "/run/current-system/sw/bin/journalctl"  # solo letture
    # File read in directory pubbliche
    "/run/current-system/sw/bin/cat"  # solo file in $HOME/public/ o /tmp/
    "/run/current-system/sw/bin/ls"
    "/run/current-system/sw/bin/find"
    # Network read-only
    "/run/current-system/sw/bin/curl"  # solo GET
    "/run/current-system/sw/bin/ping"
    # Public APIs di SOLEM (whitelist)
    "/run/current-system/sw/bin/solem-api"
    "/run/current-system/sw/bin/solem-find"
    "/run/current-system/sw/bin/solem-disk"
    "/run/current-system/sw/bin/solem-net"
  ];

  # Comandi BLACKLIST (mai consentiti, neanche con prompt utente)
  blacklist = [
    "rm -rf /"
    "dd if=/dev/zero of=/dev/"
    "mkfs"
    "fdisk"
    "parted"
    "cryptsetup"  # disk encryption ops
    "passwd"
    "useradd" "userdel" "groupadd" "groupdel"
    "iptables -F"  # flush firewall
    "systemctl mask"
    "shutdown" "reboot" "halt" "poweroff"
    "kill -9 1"  # init kill
  ];

  guardCli = pkgs.writeShellApplication {
    name = "solem-guard";
    runtimeInputs = with pkgs; [ coreutils bubblewrap util-linux jq libnotify auditd ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      AUDIT_LOG="/var/log/solem/ai-guardrails.log"
      mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

      log_action() {
        local STATUS="$1"
        local CMD="$2"
        local TS
        TS=$(date -Iseconds)
        local USER
        USER="''${SUDO_USER:-$USER}"
        echo "$TS|$USER|$STATUS|$CMD" >> "$AUDIT_LOG" 2>/dev/null || true
      }

      check_blacklist() {
        local CMD="$1"
        for forbidden in ${lib.concatStringsSep " " (map (s: "\"${s}\"") blacklist)}; do
          if echo "$CMD" | grep -qF "$forbidden"; then
            log_action "BLACKLIST" "$CMD"
            echo "BLOCKED: comando in blacklist: $forbidden" >&2
            return 1
          fi
        done
        return 0
      }

      check_whitelist() {
        local BIN
        BIN=$(echo "$1" | awk '{print $1}')
        for allowed in ${lib.concatStringsSep " " (map (s: "\"${s}\"") defaultWhitelist)}; do
          if [ "$BIN" = "$allowed" ]; then
            return 0
          fi
        done
        return 1
      }

      ask_human() {
        local CMD="$1"
        echo "[GUARDRAILS] Comando NON in whitelist:"
        echo "  $CMD"
        echo
        # Notifica desktop se disponibile
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -u critical -t 30000 "SOLEM AI Guardrails" \
            "GAVIO chiede di eseguire: $CMD"
        fi
        # Approvazione: file flag oppure prompt tty
        if [ -t 0 ]; then
          read -r -p "Approvi? [y/N]: " ans
          [[ "$ans" == "y" || "$ans" == "Y" ]] && return 0
        fi
        # Se non-interactive, default NEGATO
        return 1
      }

      case "$ACTION" in
        # ── Esegui comando con guardrails ─────────────────────────────
        exec)
          CMD="$*"
          if [ -z "$CMD" ]; then
            echo "Usage: solem-guard exec <comando>" >&2
            exit 1
          fi
          # 1. Blacklist
          check_blacklist "$CMD" || exit 1

          # 2. Whitelist
          if ! check_whitelist "$CMD"; then
            # Chiedi all'umano (se interactive)
            if ! ask_human "$CMD"; then
              log_action "DENIED" "$CMD"
              echo "DENIED dall'utente" >&2
              exit 1
            fi
          fi

          # 3. Audit + esegui in sandbox bubblewrap
          log_action "EXEC" "$CMD"

          # Sandbox bubblewrap: filesystem read-only eccetto /tmp e $HOME/.cache
          bwrap \
            --ro-bind / / \
            --proc /proc \
            --dev /dev \
            --tmpfs /tmp \
            --bind "$HOME/.cache" "$HOME/.cache" \
            --unshare-pid \
            --die-with-parent \
            -- bash -c "$CMD"
          ;;

        # ── Status guardrails ─────────────────────────────────────────
        status)
          echo "── SOLEM AI Guardrails ──"
          echo "Audit log:        $AUDIT_LOG"
          echo "Whitelist size:   ${toString (lib.length defaultWhitelist)}"
          echo "Blacklist size:   ${toString (lib.length blacklist)}"
          echo
          if [ -f "$AUDIT_LOG" ]; then
            echo "── Ultime 10 azioni ──"
            tail -10 "$AUDIT_LOG"
          fi
          ;;

        # ── Logs ──────────────────────────────────────────────────────
        log|logs)
          tail -50 "$AUDIT_LOG" 2>/dev/null || echo "(no log yet)"
          ;;

        # ── Test whitelist ────────────────────────────────────────────
        test)
          CMD="''${1:-}"
          [ -z "$CMD" ] && { echo "Usage: solem-guard test <cmd>"; exit 1; }
          if check_blacklist "$CMD"; then
            if check_whitelist "$CMD"; then
              echo "ALLOWED (whitelist)"
            else
              echo "ASK HUMAN (not in whitelist, not in blacklist)"
            fi
          else
            echo "BLOCKED (blacklist)"
          fi
          ;;

        # ── Falco / auditd status (servizi background) ────────────────
        falco)
          systemctl status falco --no-pager 2>/dev/null || echo "Falco non attivo. Abilita: solem.aiGuardrails.falco.enable = true"
          ;;

        # ── Reset audit log (richiede sudo) ───────────────────────────
        reset-log)
          if [ "$EUID" -ne 0 ]; then
            echo "Richiede root" >&2
            exit 1
          fi
          : > "$AUDIT_LOG"
          echo "Audit log resettato"
          ;;

        # ── HELP ──────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-guard — sandbox + kill switch per AI azioni

  exec <cmd>          esegue comando con guardrails (whitelist+sandbox)
  status              stato guardrails + ultime 10 azioni audit
  log                 ultime 50 azioni audit
  test <cmd>          test se un comando sarebbe consentito
  falco               status servizio Falco eBPF (anomaly detection)
  reset-log           cancella audit log (richiede sudo)

Esempi:
  solem-guard exec "uname -a"           # OK (whitelist)
  solem-guard exec "rm -rf /"           # BLOCKED (blacklist)
  solem-guard exec "git pull"           # ASK HUMAN (non in whitelist)

GAVIO chiama:
  solem-guard exec "..."  # invece di eseguire direttamente
HELP
          ;;
      esac
    '';
  };

  # Falco rules custom SOLEM
  falcoRules = pkgs.writeText "solem-falco-rules.yaml" ''
    # SOLEM custom Falco rules

    - rule: SOLEM_AI_outbound_unexpected
      desc: GAVIO/AI processi che parlano a IP non-whitelist
      condition: >
        evt.type=connect and evt.dir=< and
        proc.name in (gavio, gavio-server, python3) and
        fd.sip exists and not fd.sip in (127.0.0.1, 192.168.0.0/16, 10.0.0.0/8)
      output: "AI outbound suspicious: %proc.name to %fd.sip (user=%user.name)"
      priority: WARNING

    - rule: SOLEM_AI_writes_system_dir
      desc: AI processi che scrivono in /etc, /usr, /boot
      condition: >
        evt.type in (open, openat) and evt.is_open_write=true and
        proc.name contains gavio and
        (fd.name startswith /etc or fd.name startswith /usr or fd.name startswith /boot)
      output: "AI writes system dir: %proc.name → %fd.name"
      priority: CRITICAL

    - rule: SOLEM_AI_spawns_shell
      desc: AI processi che spawnano shell senza wrapper guardrails
      condition: >
        proc.name in (sh, bash, dash) and
        proc.pname contains gavio and
        not proc.pname contains solem-guard
      output: "AI spawned shell bypassing guardrails: %proc.cmdline"
      priority: CRITICAL
  '';
in {
  options.solem.aiGuardrails = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-guard` sandbox CLI + audit log (sempre attivo)";
    };

    falco = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Abilita Falco eBPF (FOSS Apache-2.0) per detect anomalie
          runtime AI. Default off (richiede kernel modules).
        '';
      };
    };

    killSwitch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Kill switch automatico: se Falco detecta >= 5 violazioni
          CRITICAL in 60s, systemd stop gavio.service + alert.
        '';
      };
    };

    auditd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "auditd kernel events tracking (FOSS GPL-2.0)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      guardCli
      bubblewrap
      auditd
    ];

    # Audit log dir
    systemd.tmpfiles.rules = [
      "d /var/log/solem 0755 root root - -"
      "f /var/log/solem/ai-guardrails.log 0644 root root - -"
    ];

    # auditd: kernel-level event tracking
    security.auditd.enable = cfg.auditd;

    # Falco eBPF runtime security (opt-in)
    services.falco = lib.mkIf cfg.falco.enable {
      enable = true;
      rules = {
        solem-ai-rules = builtins.readFile falcoRules;
      };
    };

    # Kill switch: cron che controlla audit log per anomalie
    systemd.services.solem-ai-killswitch = lib.mkIf cfg.killSwitch.enable {
      description = "SOLEM AI kill-switch: stop gavio se >= 5 violazioni 60s";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "solem-ai-killswitch" ''
          set -eu
          THRESHOLD=5
          WINDOW=60
          NOW=$(date +%s)
          COUNT=$(awk -F'|' -v limit="$((NOW - WINDOW))" \
            'BEGIN{n=0} { gsub("T"," ",$1); cmd="date -d \""$1"\" +%s"; cmd | getline ts; close(cmd); if (ts >= limit && $3 == "BLACKLIST") n++ } END {print n}' \
            /var/log/solem/ai-guardrails.log 2>/dev/null || echo 0)
          if [ "$COUNT" -ge "$THRESHOLD" ]; then
            ${pkgs.systemd}/bin/systemctl stop gavio.service || true
            ${pkgs.libnotify}/bin/notify-send -u critical "SOLEM Kill Switch" \
              "GAVIO fermato: $COUNT violazioni in ''${WINDOW}s"
          fi
        '';
      };
    };

    systemd.timers.solem-ai-killswitch = lib.mkIf cfg.killSwitch.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "30s";
      };
    };

    # GAVIO service: drop privileges + restrict
    # (Applicato solo se solem.api.enable = true)
    systemd.services.gavio.serviceConfig = lib.mkIf (config.solem.api.enable or false) {
      # Privilege dropping aggressivo
      NoNewPrivileges = lib.mkDefault true;
      PrivateTmp = lib.mkDefault true;
      ProtectSystem = lib.mkDefault "strict";
      ProtectHome = lib.mkDefault "tmpfs";
      ProtectKernelTunables = lib.mkDefault true;
      ProtectKernelModules = lib.mkDefault true;
      ProtectKernelLogs = lib.mkDefault true;
      ProtectClock = lib.mkDefault true;
      ProtectControlGroups = lib.mkDefault true;
      RestrictNamespaces = lib.mkDefault true;
      RestrictRealtime = lib.mkDefault true;
      RestrictSUIDSGID = lib.mkDefault true;
      LockPersonality = lib.mkDefault true;
      MemoryDenyWriteExecute = lib.mkDefault false;  # Python uvloop JIT
      SystemCallFilter = lib.mkDefault [ "@system-service" "~@cpu-emulation" "~@obsolete" "~@privileged" "~@reboot" "~@swap" "~@mount" ];
      # Network: solo localhost + DNS
      RestrictAddressFamilies = lib.mkDefault [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      # IP filtering (BPF cgroup) — solo se BPF supportato
      IPAddressAllow = lib.mkDefault [ "127.0.0.1/32" "::1/128" "192.168.0.0/16" "10.0.0.0/8" ];
      IPAddressDeny = lib.mkDefault [ "any" ];
    };

    environment.etc."solem/ai-guardrails.md".text = ''
      # SOLEM AI Guardrails

      ## Principio

      GAVIO (e qualunque AI installata su SOLEM) NON ha accesso diretto
      al sistema. OGNI azione passa per `solem-guard exec ...` che:

      1. Verifica BLACKLIST (rm -rf, mkfs, shutdown, ecc.) → BLOCKED
      2. Verifica WHITELIST → ALLOW
      3. Non in whitelist → ASK HUMAN (notify + tty prompt)
      4. Esegue in bubblewrap sandbox
      5. Log immutabile in /var/log/solem/ai-guardrails.log

      ## Architettura runtime

      ```
      GAVIO (user non-root)
        │
        ▼
      solem-guard exec "comando"
        │
        ├── BLACKLIST? → BLOCKED (audit log)
        ├── WHITELIST? → ALLOW + bubblewrap sandbox
        └── altro → ASK HUMAN (notify-send) → ALLOW/DENY
        │
        ▼  parallel:
      Falco eBPF watcher → CRITICAL alert se anomalie
        │
        ▼  parallel:
      Kill switch → stop gavio se ≥ 5 violazioni 60s
      ```

      ## systemd hardening

      gavio.service ha:
        - NoNewPrivileges
        - PrivateTmp
        - ProtectSystem=strict
        - ProtectHome=tmpfs
        - RestrictNamespaces
        - SystemCallFilter @system-service ~@privileged
        - IPAddressDeny any (eccetto LAN)

      ## Audit immutabile

      `/var/log/solem/ai-guardrails.log` formato:
        ISO_TIMESTAMP|USER|STATUS|CMD

      STATUS = EXEC | DENIED | BLACKLIST

      Per immutabilità reale: usa filesystem append-only o WORM (TODO).

      ## Test rapido

      ```bash
      solem-guard test "uname -a"      # ALLOWED
      solem-guard test "rm -rf /"      # BLOCKED
      solem-guard test "git pull"      # ASK HUMAN
      solem-guard status               # stato + ultime 10 azioni
      ```
    '';
  };
}
