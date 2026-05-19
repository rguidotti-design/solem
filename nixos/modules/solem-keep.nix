{ config, pkgs, lib, ... }:

let
  cfg = config.solem.keep;

  watchdog = pkgs.writers.writePython3 "solem-keep" {
    flakeIgnore = [
      "E501" "E741" "E226" "E231" "W291" "W293"
      "E241" "E272" "E701" "E702" "E211" "E261" "E302" "E305" "E303" "E306"
    ];
  } ''
    """solem-keep — watchdog dei servizi core SOLEM.

    Cosa fa, ogni N secondi:
      1. Polla `systemctl is-active` su tutti i servizi monitorati
      2. Se un servizio è DOWN per 2 cicli consecutivi:
         - lo riavvia (`systemctl restart`)
         - pubblica evento sul bus L3 (topic: 'system.service_down')
      3. Pubblica anche eventi 'system.service_recovered' quando torna up

    NixOS gestisce già Restart=always per i singoli servizi. solem-keep
    aggiunge l'INTEGRAZIONE col bus eventi e l'auditing centralizzato.
    """
    import json
    import logging
    import os
    import subprocess
    import time
    import urllib.request
    import urllib.error

    SERVICES = [
        "gavio",
        "solem-api",
        "ollama",
        "docker",
    ]
    INTERVAL = int(os.environ.get("SOLEM_KEEP_INTERVAL", "30"))
    EVENT_BUS = os.environ.get("SOLEM_EVENT_BUS", "http://127.0.0.1:8001/solem/events/publish")

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("solem-keep")

    state: dict[str, dict] = {svc: {"status": "unknown", "fails": 0} for svc in SERVICES}


    def systemctl(verb: str, svc: str) -> str:
        try:
            out = subprocess.run(
                ["systemctl", verb, svc],
                capture_output=True, text=True, timeout=5, check=False,
            )
            return out.stdout.strip() or out.stderr.strip()
        except subprocess.SubprocessError as e:
            return f"error: {e}"


    def is_active(svc: str) -> bool:
        return systemctl("is-active", svc) == "active"


    def publish_event(topic: str, payload: dict) -> None:
        body = json.dumps({
            "source": "solem-keep",
            "topic": topic,
            "payload": payload,
        }).encode("utf-8")
        req = urllib.request.Request(
            EVENT_BUS, data=body, method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=3) as r:
                if r.status >= 300:
                    log.warning("publish_event %s → HTTP %s", topic, r.status)
        except (urllib.error.URLError, OSError) as e:
            # Bus event giù: non bloccante, log e continua
            log.debug("publish_event %s failed: %s", topic, e)


    def loop_once() -> None:
        for svc in SERVICES:
            prev_status = state[svc]["status"]
            current_up = is_active(svc)

            if current_up:
                if prev_status == "down":
                    log.info("[%s] recovered", svc)
                    publish_event("system.service_recovered", {"service": svc})
                state[svc] = {"status": "up", "fails": 0}
            else:
                state[svc]["status"] = "down"
                state[svc]["fails"] += 1
                fails = state[svc]["fails"]
                if fails == 1:
                    log.warning("[%s] down (1st detection)", svc)
                elif fails == 2:
                    log.error("[%s] down for 2 cycles → restart", svc)
                    publish_event("system.service_down", {
                        "service": svc,
                        "consecutive_failures": fails,
                        "action": "restart",
                    })
                    result = systemctl("restart", svc)
                    log.info("[%s] restart → %s", svc, result)
                elif fails > 5:
                    # Fail-loop: smetti di insistere, segnala critico
                    if fails % 10 == 0:
                        log.critical("[%s] fail-loop %d cycles, giving up auto-restart", svc, fails)
                        publish_event("system.service_failloop", {
                            "service": svc,
                            "consecutive_failures": fails,
                        })


    def main() -> None:
        log.info("solem-keep started, interval=%ds, services=%s", INTERVAL, SERVICES)
        publish_event("system.solem_keep_started", {"services": SERVICES, "interval": INTERVAL})
        while True:
            try:
                loop_once()
            except Exception as e:
                log.exception("loop iteration failed: %s", e)
            time.sleep(INTERVAL)


    if __name__ == "__main__":
        main()
  '';
in {
  options.solem.keep = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;  # attivo di default — non blocca nulla, solo monitora
      description = "Watchdog servizi core SOLEM + integrazione event bus.";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Polling interval in secondi.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.solem-keep = {
      description = "SOLEM Keep — watchdog dei servizi core + event bus integration";
      after = [ "network-online.target" "solem-api.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # PATH per systemctl
      path = with pkgs; [ systemd ];

      environment = {
        SOLEM_KEEP_INTERVAL = toString cfg.interval;
        SOLEM_EVENT_BUS = "http://127.0.0.1:8001/solem/events/publish";
        PYTHONUNBUFFERED = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = "root";  # serve per systemctl restart
        ExecStart = "${pkgs.python312}/bin/python ${watchdog}";
        Restart = "always";
        RestartSec = "15s";

        # Risorse minime — è solo polling
        MemoryMax = "64M";
        CPUQuota = "10%";
        Nice = 10;
        IOSchedulingClass = "idle";

        # ── HARDENING STRICT (M1.1) ─────────────────────────────────
        # solem-keep è puro: polla systemctl is-active + POST localhost.
        # Non ha bisogno di sudo, no rete pubblica, no /home, no devices.

        # No privilege escalation
        NoNewPrivileges = true;

        # Filesystem protection
        ProtectSystem = "strict";       # /usr /boot /etc → read-only
        ProtectHome = "tmpfs";          # /home /root /run/user → tmpfs vuoto
        PrivateTmp = true;              # /tmp /var/tmp privati per il servizio
        ProtectKernelTunables = true;   # /proc/sys read-only
        ProtectKernelModules = true;    # no load/unload moduli kernel
        ProtectKernelLogs = true;       # no accesso syslog kernel
        ProtectControlGroups = true;    # cgroups read-only
        ProtectClock = true;            # no modifiche system clock
        ProtectHostname = true;         # no modifiche hostname
        ProtectProc = "invisible";      # /proc nascosto eccetto proprio PID

        # Device protection (no /dev/* eccetto null/zero/random)
        PrivateDevices = true;

        # Network: solo localhost
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        IPAddressDeny = "any";
        IPAddressAllow = [ "127.0.0.1" "::1" ];

        # Process flags
        LockPersonality = true;         # no change personality (es. exec mode)
        RestrictRealtime = true;        # no real-time scheduling
        RestrictSUIDSGID = true;        # no setuid/setgid binaries
        RestrictNamespaces = true;      # no creation new namespaces
        RemoveIPC = true;               # cleanup IPC al exit

        # System call filter (block tutto eccetto base + systemctl)
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        SystemCallErrorNumber = "EPERM";
        SystemCallArchitectures = "native";

        # Memory write-execute (Python OK senza JIT)
        MemoryDenyWriteExecute = true;

        # Capabilities: nessuna (default; explicit per chiarezza)
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        # UMask restrittivo
        UMask = "0077";
      };
    };
  };
}
