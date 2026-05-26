{ config, pkgs, lib, ... }:

# SOLEM GAVIO ZERO-TRUST — overlay che forza il service gavio.service
# a girare come gavio-ai (UID 970) con capability drop totale,
# NoNewPrivileges, syscall filter strict, PrivateDevices, MAC-style hardening.
#
# Single responsibility: SOLO override del serviceConfig di gavio.service.
# Non sostituisce gavio.nix (che resta sorgente di verità del service base),
# NON configura l'utente (vedi solem-ai-user.nix), NON il firewall
# (vedi solem-ai-network.nix).
#
# Conflitto deliberato con ai-freedom.nix:
#   - ai-freedom.nix: AI libera, sudo NOPASSWD per `gavio`.
#   - zero-trust:     AI ingabbiata, gira come `gavio-ai`, NO sudo.
#
# Le due cose sono incompatibili by design. Default OFF per non rompere
# setup esistenti. Per attivare:
#   solem.gavioZeroTrust.enable = true;
#   # disabilita anche ai-freedom se importato
#
# LIMITI ONESTI:
#   - GAVIO oggi non e' ancora packaged → questo modulo prepara il terreno.
#   - Quando il binary GAVIO sara' pronto, ExecStart andra' verificato a
#     mano (subprocess che richiedevano sudo come system_control.py non
#     funzioneranno piu', dovranno passare per solem-guard).
#   - VM test verifica che le override siano APPLICATE, non l'esecuzione
#     end-to-end di GAVIO (richiede /opt/gavio mounted + python deps).

let
  cfg = config.solem.gavioZeroTrust;
  aiUser = config.solem.aiUser.username or "gavio-ai";
in {
  options.solem.gavioZeroTrust = {
    enable = lib.mkEnableOption "Override gavio.service per girare come gavio-ai isolato";

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gavio-ai/workdir";
      description = "Working directory dell'AI (scrittura permessa)";
    };

    sourceDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/gavio";
      description = ''
        Source code dir di GAVIO. Sara' montata READ-ONLY per gavio-ai.
        L'utente umano deve fare chown manuale o usare bind mount.
      '';
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Limite RAM (systemd MemoryMax)";
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "200%";
      description = "Limite CPU (es. 200% = 2 cores)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.solem.aiUser.enable;
        message = ''
          solem.gavioZeroTrust richiede solem.aiUser.enable = true
          (per esistenza utente gavio-ai).
        '';
      }
    ];

    # Tmpfiles: garantisce workdir esista con permessi corretti
    systemd.tmpfiles.rules = [
      "d ${cfg.workDir} 0700 ${aiUser} ${aiUser} -"
      "d /var/log/gavio-ai 0750 ${aiUser} ${aiUser} -"
    ];

    # Override del service gavio (richiede che gavio.nix sia importato altrove)
    systemd.services.gavio = {
      serviceConfig = {
        # ── Identita': gira come gavio-ai, NON gavio ─────────────────
        User = lib.mkForce aiUser;
        Group = lib.mkForce aiUser;

        WorkingDirectory = lib.mkForce cfg.workDir;

        # ── Capability drop TOTALE ───────────────────────────────────
        # gavio-ai non ha NESSUNA capability Linux. Niente CAP_NET_ADMIN,
        # CAP_SYS_PTRACE, CAP_DAC_OVERRIDE, niente di niente.
        CapabilityBoundingSet = lib.mkForce "";
        AmbientCapabilities = lib.mkForce "";

        # ── NoNewPrivileges: non puo' setuid root, non puo' exec sudo ─
        NoNewPrivileges = lib.mkForce true;

        # ── Device isolation ─────────────────────────────────────────
        PrivateDevices = lib.mkForce true;    # solo /dev/null, /dev/zero, /dev/random, /dev/urandom
        ProtectHostname = lib.mkForce true;
        ProtectClock = lib.mkForce true;
        ProtectKernelTunables = lib.mkForce true;
        ProtectKernelModules = lib.mkForce true;
        ProtectKernelLogs = lib.mkForce true;
        ProtectControlGroups = lib.mkForce true;
        ProtectProc = lib.mkForce "invisible";   # /proc vede solo i suoi PID
        ProcSubset = lib.mkForce "pid";          # niente /proc/sys, /proc/sysrq-trigger

        # ── Filesystem: tutto readonly tranne workdir ────────────────
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce "tmpfs";  # /home nascosto come tmpfs vuota
        PrivateTmp = lib.mkForce true;
        # NB: /var/lib/gavio-ai/ e' di gavio-ai. /opt/gavio e' source readonly.
        ReadWritePaths = lib.mkForce [
          cfg.workDir
          "/var/lib/gavio-ai"
          "/var/log/gavio-ai"
        ];
        ReadOnlyPaths = lib.mkForce [
          cfg.sourceDir         # source code in sola lettura
          "/etc/gavio"          # config in sola lettura
        ];

        # ── Memory protection ────────────────────────────────────────
        MemoryDenyWriteExecute = lib.mkForce false;  # Python JIT richiede WX (httpx/grpc)
        LockPersonality = lib.mkForce true;
        RestrictRealtime = lib.mkForce true;
        RestrictSUIDSGID = lib.mkForce true;
        RestrictNamespaces = lib.mkForce true;       # niente unshare, niente container privati
        RemoveIPC = lib.mkForce true;

        # ── Syscall filter STRICT ────────────────────────────────────
        # @system-service e' baseline ragionevole. Togliamo tutto cio'
        # che permette privilege escalation o lateral movement.
        SystemCallFilter = lib.mkForce [
          "@system-service"
          "~@privileged"           # niente cose tipo capset, setfsuid, ecc.
          "~@resources"            # niente nice, setrlimit fuori limiti
          "~@cpu-emulation"
          "~@debug"                # niente ptrace, process_vm_*
          "~@module"               # niente init_module, delete_module
          "~@mount"                # niente mount/umount
          "~@obsolete"
          "~@raw-io"               # niente ioperm, iopl
          "~@reboot"
          "~@swap"
          "~@keyring"              # niente keyctl (vault leak protection)
        ];
        SystemCallErrorNumber = lib.mkForce "EPERM";
        SystemCallArchitectures = lib.mkForce "native";

        # ── Network: solo AF_UNIX + AF_INET + AF_INET6 ───────────────
        # Resta filtrato dal nftables egress (solem-ai-network).
        RestrictAddressFamilies = lib.mkForce [ "AF_UNIX" "AF_INET" "AF_INET6" ];

        # ── Risorse ──────────────────────────────────────────────────
        MemoryMax = lib.mkForce cfg.memoryMax;
        CPUQuota = lib.mkForce cfg.cpuQuota;
        TasksMax = lib.mkForce 256;
        LimitNOFILE = lib.mkForce 4096;

        # ── UMask restrittivo ────────────────────────────────────────
        UMask = lib.mkForce "0077";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-gavio-check";
        runtimeInputs = with pkgs; [ systemd coreutils ];
        text = ''
          echo "── SOLEM GAVIO Zero-Trust Check ──"
          if ! systemctl cat gavio.service >/dev/null 2>&1; then
            echo "gavio.service non definito"
            exit 1
          fi

          EXEC=$(systemctl show gavio.service -p User --value)
          echo "User configurato:    $EXEC"
          [ "$EXEC" = "${aiUser}" ] && echo "  ✓ gira come ${aiUser}" \
            || echo "  ✗ FAIL: gira come '$EXEC', atteso ${aiUser}"

          NNP=$(systemctl show gavio.service -p NoNewPrivileges --value)
          echo "NoNewPrivileges:     $NNP"
          if [ "$NNP" = "yes" ]; then echo "  ✓ NNP attivo"; else echo "  ✗ FAIL: NNP off"; fi

          CAP=$(systemctl show gavio.service -p CapabilityBoundingSet --value)
          echo "CapabilityBoundingSet: $CAP"
          if [ -z "$CAP" ] || [ "$CAP" = "0" ]; then
            echo "  ✓ NO capability"
          else
            echo "  ⚠ capability presenti: $CAP"
          fi

          PRV=$(systemctl show gavio.service -p PrivateDevices --value)
          echo "PrivateDevices:      $PRV"
          if [ "$PRV" = "yes" ]; then echo "  ✓ device isolato"; else echo "  ✗ device condivisi"; fi

          echo
          echo "── systemd-analyze security (esposizione service) ──"
          systemd-analyze security gavio.service 2>/dev/null | head -20 || \
            echo "(richiede systemd-analyze, prova manualmente)"
        '';
      })
    ];

    environment.etc."solem/gavio-zero-trust.md".text = ''
      # SOLEM GAVIO Zero-Trust Mode

      Quando `solem.gavioZeroTrust.enable = true`:

        - gavio.service gira come UID 970 (gavio-ai), NON 1000 (gavio)
        - CapabilityBoundingSet = "" → ZERO capability Linux
        - NoNewPrivileges = true → no setuid, no sudo possibile
        - PrivateDevices, ProtectKernel*, ProtectProc=invisible
        - ReadWritePaths solo /var/lib/gavio-ai + workdir
        - /opt/gavio readonly per l'AI
        - SystemCallFilter: ~@privileged ~@module ~@mount ~@keyring ecc.
        - TasksMax 256, MemoryMax 2G, CPUQuota 200%

      ## Conflitto con ai-freedom.nix

      Se hai `ai-freedom.nix` importato, le sue direttive "AI libera"
      vengono OVERRIDATE per gavio.service. L'AI smette di avere sudo.

      Le funzioni di GAVIO che richiedevano sudo (system_control.py,
      pc_actions.py) devono passare per `solem-guard exec`, che fa
      da choke point con audit log + decisione human-in-loop.

      ## Verifica

      ```
      solem-gavio-check
      ```

      ## Migrazione

      1. Sposta source GAVIO: chown -R root:root /opt/gavio (readonly per AI).
      2. Sposta venv: il bootstrap originale crea /var/lib/gavio/venv,
         questo modulo punta a /var/lib/gavio-ai. Va spostato manualmente
         o rebooted con tmpfiles auto-create.
      3. Disabilita services.openssh.allowedUsers che permette login a gavio
         se vuoi separare anche login fisico (Step 4+).

      ## Cosa NON copre

      - Exploit kernel: NNP + caps drop NON salva da privilege escalation
        via kernel vuln (CVE locali).
      - LLM prompt injection: l'AI puo' essere ancora "convinta" via prompt
        a fare cose dannose nei suoi limiti (l'isolamento limita il blast,
        non previene il convincimento).
      - Side-channel (timing, Spectre): non coperti.
    '';
  };
}
