{ config, pkgs, lib, ... }:

# SOLEM PROCESS SENTINEL — anomaly detector processi locale.
#
# Single responsibility: SOLO daemon Python che ogni N secondi:
#   1. Snapshot /proc → lista processi + cpu + mem + cmdline + parent
#   2. Detect pattern sospetti:
#      - Processo high-CPU per > 5 min senza pattern normale
#      - Cmdline contiene strings malware-like (curl|sh, /tmp/.X, miners)
#      - Binari da location sospette (/tmp, /dev/shm, /run/user)
#      - Processo orphano (PPID 1) non riconosciuto
#      - Connessioni outbound a porte note malware (4444, 6666, ...)
#   3. Log + notify-send su match
#   4. KILL automatic opt-in (default off — solo log+alert)
#
# Tutto Python stdlib + /proc + ss (iproute2). Niente cloud.
# Niente ML — solo rule-based per ora (poi roadmap ML opt-in).

let
  cfg = config.solem.processSentinel;

  sentinelDaemon = pkgs.writers.writePython3 "solem-process-sentinel" {
    flakeIgnore = [ "E501" "W291" "W293" "E402" "E741" ];
  } ''
    """SOLEM Process Sentinel — rule-based anomaly detector."""
    import json
    import os
    import re
    import socket
    import subprocess
    import time
    from pathlib import Path

    # ── Config ─────────────────────────────────────────────────────
    INTERVAL = int(os.environ.get("SENTINEL_INTERVAL", "30"))
    LOG_FILE = os.environ.get("SENTINEL_LOG", "/var/log/solem/process-sentinel.log")
    KILL_ENABLED = os.environ.get("SENTINEL_KILL", "0") == "1"

    # Cmdline pattern sospetti
    SUSPICIOUS_CMDLINE_PATTERNS = [
        r"curl.*\|.*sh",                  # curl | sh remote exec
        r"wget.*\|.*sh",                  # idem wget
        r"bash.*-c.*base64.*decode",      # encoded shell
        r"/tmp/\.[a-zA-Z0-9]{4,}",        # hidden binary in /tmp
        r"/dev/shm/\.[a-zA-Z0-9]",        # hidden in /dev/shm
        r"xmrig",                          # crypto miner Monero
        r"cpuminer",                       # generic crypto miner
        r"kdevtmpfsi",                     # known coinminer
        r"kthrotlds",                      # known coinminer hidden name
        r"\.so\.\d+\.\d+\.\d+\.so",       # double extension suspicious
    ]
    SUSPICIOUS_PATHS = ["/tmp/", "/dev/shm/", "/run/user/"]

    # Porte outbound sospette
    SUSPICIOUS_PORTS = {4444, 6666, 31337, 12345, 1337, 8333, 9050}

    # ── State ──────────────────────────────────────────────────────
    cpu_history: dict[int, list[float]] = {}  # pid → [cpu%, ...]


    def log_event(level: str, msg: str, pid: int = -1, cmdline: str = ""):
        """Log immutabile su /var/log/solem/."""
        ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        line = f"{ts}|{level}|pid={pid}|{cmdline[:200]}|{msg}\n"
        try:
            Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
            with open(LOG_FILE, "a") as f:
                f.write(line)
        except OSError:
            pass
        # Notifica desktop se possibile
        if level in ("ALERT", "CRITICAL"):
            try:
                subprocess.run(
                    ["notify-send", "-u", "critical", "-t", "30000",
                     "SOLEM Process Sentinel", f"{msg}\nPID {pid}: {cmdline[:80]}"],
                    timeout=2, check=False,
                )
            except (subprocess.SubprocessError, FileNotFoundError):
                pass


    def read_proc() -> list[dict]:
        """Snapshot /proc → lista dict processi."""
        out = []
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            try:
                with open(entry / "cmdline", "rb") as f:
                    cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", errors="ignore").strip()
                if not cmdline:
                    continue
                with open(entry / "status") as f:
                    status = f.read()
                with open(entry / "stat") as f:
                    stat = f.read().split()
                exe = ""
                try:
                    exe = os.readlink(entry / "exe")
                except OSError:
                    pass
                ppid = int(re.search(r"PPid:\s+(\d+)", status).group(1)) if re.search(r"PPid:\s+(\d+)", status) else 0
                vm_rss = int(re.search(r"VmRSS:\s+(\d+)", status).group(1)) if re.search(r"VmRSS:\s+(\d+)", status) else 0
                out.append({
                    "pid": pid, "ppid": ppid, "cmdline": cmdline,
                    "exe": exe, "rss_kb": vm_rss,
                    "utime": int(stat[13]), "stime": int(stat[14]),
                })
            except (FileNotFoundError, PermissionError, ValueError, OSError):
                continue
        return out


    def check_suspicious_cmdline(proc: dict) -> str | None:
        """Rule-based: cmdline match pattern sospetti."""
        cmdline = proc["cmdline"]
        for pat in SUSPICIOUS_CMDLINE_PATTERNS:
            if re.search(pat, cmdline, re.IGNORECASE):
                return f"cmdline match pattern '{pat}'"
        for path in SUSPICIOUS_PATHS:
            if proc["exe"].startswith(path):
                return f"exe in sospetta {path}"
        return None


    def check_outbound_connections() -> list[dict]:
        """Lista connessioni TCP outbound con destinazione porte sospette."""
        suspects = []
        try:
            ss = subprocess.run(["ss", "-tnp", "state", "established"],
                                capture_output=True, text=True, timeout=5, check=False)
            for line in ss.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) < 5:
                    continue
                remote = parts[4]
                if ":" not in remote:
                    continue
                try:
                    port = int(remote.rsplit(":", 1)[1])
                except ValueError:
                    continue
                if port in SUSPICIOUS_PORTS:
                    proc_info = parts[5] if len(parts) > 5 else ""
                    suspects.append({"remote": remote, "port": port, "proc": proc_info})
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
        return suspects


    def maybe_kill(pid: int, reason: str):
        if not KILL_ENABLED:
            return
        try:
            os.kill(pid, 15)  # SIGTERM
            log_event("KILL", f"PID {pid} killed: {reason}", pid=pid)
        except (PermissionError, ProcessLookupError):
            pass


    def main():
        log_event("START", f"Sentinel avviato, interval={INTERVAL}s, kill={KILL_ENABLED}")
        while True:
            try:
                procs = read_proc()

                # 1. Check cmdline / exe sospetti
                for proc in procs:
                    reason = check_suspicious_cmdline(proc)
                    if reason:
                        log_event("ALERT", reason, pid=proc["pid"], cmdline=proc["cmdline"])
                        maybe_kill(proc["pid"], reason)

                # 2. Check outbound connections sospette
                outbound = check_outbound_connections()
                for sus in outbound:
                    log_event("ALERT",
                              f"Outbound a porta sospetta {sus['port']}: {sus['remote']} {sus['proc']}")

                # 3. High-CPU sustained tracking
                for proc in procs:
                    pid = proc["pid"]
                    cpu_total = proc["utime"] + proc["stime"]
                    hist = cpu_history.setdefault(pid, [])
                    hist.append(cpu_total)
                    if len(hist) > 10:
                        hist.pop(0)
                    if len(hist) == 10:
                        delta = hist[-1] - hist[0]
                        if delta > 9000:  # ~ 100% CPU per 10 cicli
                            log_event("WARN",
                                      f"Sustained high CPU 5+ min (delta jiffies={delta})",
                                      pid=pid, cmdline=proc["cmdline"])

                # Cleanup pid scomparsi
                alive_pids = {p["pid"] for p in procs}
                for pid in list(cpu_history):
                    if pid not in alive_pids:
                        del cpu_history[pid]

            except Exception as e:  # noqa: BLE001
                log_event("ERROR", f"Sentinel exception: {e}")
            time.sleep(INTERVAL)


    if __name__ == "__main__":
        main()
  '';

  sentinelCli = pkgs.writeShellApplication {
    name = "solem-sentinel";
    runtimeInputs = with pkgs; [ coreutils systemd ];
    text = ''
      ACTION="''${1:-status}"
      LOG="/var/log/solem/process-sentinel.log"

      case "$ACTION" in
        log|logs)
          tail -50 "$LOG" 2>/dev/null || echo "(no log yet)"
          ;;
        tail|follow)
          tail -F "$LOG" 2>/dev/null
          ;;
        alerts)
          grep -E "ALERT|CRITICAL" "$LOG" 2>/dev/null | tail -20 || echo "(no alerts)"
          ;;
        status)
          echo "── SOLEM Process Sentinel ──"
          systemctl status solem-process-sentinel --no-pager 2>/dev/null | head -10 || echo "(service non attivo)"
          echo
          if [ -f "$LOG" ]; then
            COUNT=$(wc -l < "$LOG")
            ALERTS=$(grep -c "ALERT" "$LOG" 2>/dev/null || echo 0)
            echo "Log entries: $COUNT"
            echo "Alerts:      $ALERTS"
            echo
            echo "── Ultime 5 entry ──"
            tail -5 "$LOG"
          fi
          ;;
        test)
          echo "── Test daemon esecuzione manuale ──"
          SENTINEL_INTERVAL=5 SENTINEL_KILL=0 ${sentinelDaemon} &
          PID=$!
          sleep 10
          kill "$PID" 2>/dev/null || true
          echo "Test completato. Vedi log: solem-sentinel log"
          ;;
        *)
          cat <<'HELP'
solem-sentinel — process anomaly detector (rule-based)

  status         daemon attivo? quanti alert?
  log            ultime 50 entry
  tail           follow live
  alerts         solo ALERT/CRITICAL
  test           esegui 10s in foreground (debug)

Detection:
  - cmdline patterns malware (curl|sh, xmrig, kdevtmpfsi, ...)
  - exe in /tmp /dev/shm /run/user
  - outbound a porte sospette (4444, 6666, 31337, ...)
  - sustained high-CPU 5+ min (warning)

Kill automatico: solem.processSentinel.kill = true (default false).

Tutto FOSS. Python stdlib + /proc + ss. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.processSentinel = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Daemon process anomaly detector (rule-based, no ML).
        Default off (CPU ~0.5% costante, ma alcuni hanno paura del
        background monitoring).
      '';
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Secondi tra snapshot /proc";
    };

    kill = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Kill automatico processi flaggati ALERT.
        Default false (solo log + notify). Abilita SOLO se sicuro.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      sentinelCli
      sentinelDaemon
    ];

    systemd.tmpfiles.rules = [
      "d /var/log/solem 0755 root root - -"
      "f /var/log/solem/process-sentinel.log 0644 root root - -"
    ];

    systemd.services.solem-process-sentinel = {
      description = "SOLEM Process Sentinel — anomaly detector";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${sentinelDaemon}";
        Environment = [
          "SENTINEL_INTERVAL=${toString cfg.interval}"
          "SENTINEL_KILL=${if cfg.kill then "1" else "0"}"
        ];
        Restart = "on-failure";
        RestartSec = 10;
        # Hardening: il sentinel deve leggere /proc ma niente di più
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/log/solem" ];
        ProtectHome = "tmpfs";
        PrivateTmp = true;
        NoNewPrivileges = true;
        # Necessario: read /proc (capability)
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        # Niente network outbound (sentinel non chiama nessuno)
        IPAddressDeny = "any";
      };
    };

    environment.etc."solem/process-sentinel.md".text = ''
      # SOLEM Process Sentinel

      ## Cosa fa

      Daemon Python che ogni ${toString cfg.interval}s:
        1. Snapshot /proc → lista processi
        2. Detect 4 categorie anomalie:
           - Cmdline match pattern malware (curl|sh, xmrig, miners)
           - Exe in /tmp /dev/shm /run/user (binari hidden)
           - Outbound a porte sospette (4444 metasploit, 6666 IRC,
             31337 elite, 8333 BTC, 9050 Tor)
           - Sustained high-CPU 5+ min (warning, non kill)
        3. Log immutabile /var/log/solem/process-sentinel.log
        4. notify-send CRITICAL su match
        5. (opt-in) KILL automatic SIGTERM

      ## Kill switch

      `solem.processSentinel.kill = true` → kill auto SIGTERM su ALERT.
      Default false: solo log + notify. Sicuro per non-sysadmin.

      ## systemd hardening (per il sentinel stesso)

      Il sentinel è il primo target di chi vuole disabilitare detection.
      Hardenato con:
        - ProtectSystem = strict
        - ProtectHome = tmpfs (no accesso $HOME utente)
        - IPAddressDeny = any (no network)
        - NoNewPrivileges, PrivateTmp

      ## False positive

      `curl | sh` può essere legit (es. `curl install.nix.sh | sh`).
      Soluzione: whitelist (TODO opzione `solem.processSentinel.whitelist`).
    '';
  };
}
