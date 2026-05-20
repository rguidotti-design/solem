{ config, pkgs, lib, ... }:

let
  pyDeps = pkgs.python312.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    httpx
    python-multipart  # richiesto da voice.py per UploadFile/File
    aiofiles          # per FileResponse async
    cryptography      # Ed25519 vero per federation.py (no HMAC fallback in prod)
  ]);
in {
  # SOLEM API — primo backend NATIVO di SOLEM (Layer 1-4 stub).
  # Separato da GAVIO: gira su :8001 mentre GAVIO sta su :8000.
  # Questa è la radice della filosofia AI-native: un'API pensata perché
  # le AI (GAVIO oggi, altre AI domani) possano scoprire e usare SOLEM.

  systemd.services.solem-api = {
    description = "SOLEM API — backend di sistema (L1-L5 + users + system)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # PATH per i subprocess che SOLEM API esegue
    # (nix-env per /system/generations, systemctl per /system/update,
    # sudo per /system/rebuild + /system/rollback)
    path = with pkgs; [
      nix
      systemd      # systemctl
      sudo
      nixos-rebuild
      coreutils
    ];

    environment = {
      GAVIO_API_URL = "http://127.0.0.1:8000";
      SOLEM_DB_PATH = "/var/lib/solem/solem.db";
      PYTHONUNBUFFERED = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = "gavio";
      Group = "users";
      WorkingDirectory = "/opt/solem-backend";

      ExecStart = pkgs.writeShellScript "solem-api-start" ''
        set -euo pipefail
        cd /opt/solem-backend
        exec ${pyDeps}/bin/python -m uvicorn solem_api.main:app \
          --host 0.0.0.0 \
          --port 8001 \
          --log-level info
      '';

      Restart = "always";
      RestartSec = "5s";

      MemoryMax = "512M";
      CPUQuota = "100%";

      # ── HARDENING MEDIUM (M1.1) ─────────────────────────────────────
      # solem-api esegue subprocess sudo (nixos-rebuild, systemctl) → NO
      # NoNewPrivileges, NO PrivateDevices. Mantiene tutti gli altri flag.

      # Filesystem protection (solem-api scrive solo in /var/lib/solem)
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/var/lib/solem"        # SQLite DB
        "/var/log/solem"        # audit log futuro
        "/var/lib/solem-ca"     # se zero-trust attivo
      ];
      ProtectHome = "tmpfs";    # niente /home
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      # ProtectProc disabilitato → /system/info legge /proc per uptime/memory

      # Device protection
      # PrivateDevices = false  (esplicito: serve per /system/info procfs)

      # Network: localhost + outbound per GAVIO discovery + Ollama
      # Niente IPAddressDeny: la dashboard è esposta su 0.0.0.0:8001
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];

      # Process flags
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      # RestrictNamespaces disabilitato (sudo nixos-rebuild può aver bisogno)

      # System call filter — permissivo per sudo/subprocess
      SystemCallFilter = [
        "@system-service"
        "~@cpu-emulation"
        "~@obsolete"
      ];
      SystemCallErrorNumber = "EPERM";
      SystemCallArchitectures = "native";

      # NB: MemoryDenyWriteExecute disabled — Python uvloop usa JIT compile
      # MemoryDenyWriteExecute = false;

      # NB: NoNewPrivileges disabled — solem-api invoca sudo nixos-rebuild
      # via /system/rebuild API. Senza questo, sudo viene bloccato.
      # NoNewPrivileges = false;

      # UMask
      UMask = "0027";
    };
  };

  # Timer: snapshot context ogni 5 minuti (L2 Context Engine)
  systemd.services.solem-context-snapshot = {
    description = "SOLEM — snapshot context periodico (L2)";
    after = [ "solem-api.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gavio";
      ExecStart = pkgs.writeShellScript "solem-ctx-snap" ''
        ${pkgs.curl}/bin/curl -fsS -X POST http://127.0.0.1:8001/solem/context/snapshot \
          -H 'Content-Type: application/json' \
          -d '{"active_role": null, "current_task": null, "apps_open": []}' \
          > /dev/null 2>&1 || true
      '';
    };
  };

  systemd.timers.solem-context-snapshot = {
    description = "Trigger snapshot context ogni 5 minuti";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };
}
