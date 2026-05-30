{ config, pkgs, lib, ... }:

# SOLEM APPARMOR — Mandatory Access Control kernel-enforced.
#
# Single responsibility: SOLO abilitazione AppArmor + profilo per i
# processi AI (gavio.service). Non sostituisce i layer precedenti
# (user separation, network filter, syscall filter), li RINFORZA a
# livello kernel: anche se l'AI riesce in qualche modo ad aggirare
# systemd hardening, AppArmor enforced dal kernel rifiuta access.
#
# AppArmor vs altri:
#   - DAC (chmod 0700) → owner-based, bypassato da root
#   - systemd ReadOnlyPaths → userspace bind mount, bypassato da exploit
#   - AppArmor → kernel-enforced policy, NON bypassabile da userspace
#
# Profili creati:
#   - solem-gavio-ai → confina python3 + venv di gavio-ai
#   - solem-ollama   → confina ollama (model server)
#
# Tutto FOSS (AppArmor LSM kernel + apparmor-utils). 0 €.
#
# LIMITI ONESTI:
#   - Profile development e' fragile: cambio path Python → re-tuning.
#   - Profili sono SCAFFOLD: senza GAVIO reale packaged, l'enforcement
#     puo' rompere comportamenti legittimi non testati.
#   - Modalita' "complain" sviluppata prima di "enforce" per evitare
#     break a produzione. Default complain, opt-in enforce.
#   - Non protegge da kernel exploit che bypassano LSM (rari ma esistono).
#   - Non rimpiazza Secure Boot + TPM.

let
  cfg = config.solem.apparmor;
  aiHome = "/var/lib/gavio-ai";

  # Profilo per il process AI (gavio-ai venv python)
  gavioAiProfile = ''
    abi <abi/3.0>,
    include <tunables/global>

    # Profilo nominale: confina qualsiasi exec di python3 quando lanciato
    # all'interno del venv di gavio-ai. Il path matchara' il binary del venv.
    profile solem-gavio-ai ${aiHome}/venv/bin/python3 {
      include <abstractions/base>
      # abstractions/python NON presente in tutte le versioni apparmor-profiles;
      # le permission Python (read /usr/lib/python*, /tmp/__pycache__) sono
      # gia' coperte dalle regole /usr/** r, /tmp/** rwk sotto.
      include <abstractions/ssl_certs>

      # ── Filesystem: read-only quasi tutto ─────────────────────────
      # NB: "mrix" = mmap + read + execute (inherit child).
      # - m: mmap shared libs (libreadline, libc, libpython, ...)
      # - r: read
      # - i: ipc-inherit (eredita profilo su exec interno)
      # - x: execute (cat, sed, jq sotto bash/python)
      # Solo "r" o "mr" produce DENIED su mmap .so o exec binaries.
      /usr/** mrix,
      /run/current-system/** mrix,
      /nix/store/** mrix,
      /etc/ssl/** r,
      /etc/resolv.conf r,
      /etc/nsswitch.conf r,
      /etc/hosts r,

      # ── Home AI: read/write SOLO la propria ──────────────────────
      ${aiHome}/ r,
      ${aiHome}/** rwk,

      # ── Codice GAVIO: readonly ───────────────────────────────────
      /opt/gavio/ r,
      /opt/gavio/** r,

      # ── /etc/gavio config: solo read ─────────────────────────────
      /etc/gavio/ r,
      /etc/gavio/** r,

      # ── /tmp e /var/tmp: read/write (PrivateTmp di systemd) ──────
      /tmp/** rwk,
      /var/tmp/** rwk,

      # ── /proc: solo i propri PID (ProtectProc=invisible aiuta) ────
      @{PROC}/@{pid}/** r,
      @{PROC}/sys/kernel/random/uuid r,
      @{PROC}/cpuinfo r,
      @{PROC}/meminfo r,
      @{PROC}/stat r,
      @{PROC}/loadavg r,

      # ── DENY: dati utente umano ──────────────────────────────────
      deny /home/gavio/** rwx,
      deny /root/** rwx,
      deny /home/** rwx,

      # ── DENY: credenziali di sistema ─────────────────────────────
      deny /etc/shadow r,
      deny /etc/gshadow r,
      deny /etc/sudoers r,
      deny /etc/sudoers.d/** r,
      deny /etc/ssh/ssh_host_*_key r,

      # ── DENY: kernel interfaces sensibili ────────────────────────
      deny /dev/mem rwx,
      deny /dev/kmem rwx,
      deny /dev/kallsyms r,
      deny /proc/kallsyms r,
      deny /proc/kcore rwx,
      deny /sys/kernel/security/** rwx,
      deny /sys/firmware/** rwx,
      deny /boot/** rwx,

      # ── DENY: ptrace su altri processi ───────────────────────────
      deny ptrace,
      deny @{PROC}/[0-9]*/mem rwx,

      # ── DENY: load kernel modules ────────────────────────────────
      deny capability sys_module,
      deny /sbin/insmod x,
      deny /sbin/modprobe x,

      # ── Network: limitato a localhost + DNS allowlist ────────────
      # AppArmor network e' coarse-grained (allow/deny family).
      # Filtro fine via nftables (solem-ai-network).
      network inet stream,
      network inet dgram,
      network inet6 stream,
      network inet6 dgram,
      network unix stream,
      network unix dgram,
      deny network raw,
      deny network packet,

      # ── Capability: drop tutto tranne uso normale ────────────────
      deny capability sys_admin,
      deny capability sys_ptrace,
      deny capability sys_rawio,
      deny capability sys_boot,
      deny capability sys_chroot,
      deny capability dac_override,
      deny capability dac_read_search,
      deny capability fowner,
      deny capability setuid,
      deny capability setgid,

      # ── exec child: Pix = try profile, fallback inherit ──────────
      # Pix evita il fail di Px quando non esiste un profilo dedicato
      # per il binary child (es. cat, sed, jq).
      /run/current-system/sw/bin/* Pix,
      /usr/bin/* Pix,
      ${aiHome}/venv/bin/* Pix,

      # ── Signal: puo' inviare a se stesso, non ad altri ───────────
      signal (send) peer=solem-gavio-ai,
      signal (receive),
    }
  '';

  # Profilo per ollama (model server, riceve query da GAVIO via 11434)
  ollamaProfile = ''
    abi <abi/3.0>,
    include <tunables/global>

    profile solem-ollama /run/current-system/sw/bin/ollama {
      include <abstractions/base>
      include <abstractions/ssl_certs>
      include <abstractions/nameservice>

      # Ollama scarica modelli + li tiene in cache
      /var/lib/ollama/ r,
      /var/lib/ollama/** rwk,

      # Read-only system + nix store (mrix = mmap + read + execute + inherit)
      /usr/** mrix,
      /run/current-system/** mrix,
      /nix/store/** mrix,
      /etc/ssl/** r,
      /etc/resolv.conf r,
      /etc/hosts r,
      /etc/nsswitch.conf r,

      # GPU device (se presente, ollama lo usa)
      /dev/nvidia* rw,
      /dev/dri/** rw,

      # /proc: solo propri
      @{PROC}/@{pid}/** r,
      @{PROC}/cpuinfo r,
      @{PROC}/meminfo r,
      @{PROC}/stat r,

      # /tmp
      /tmp/** rwk,
      /var/tmp/** rwk,

      # DENY user data
      deny /home/** rwx,
      deny /root/** rwx,
      deny /etc/shadow r,
      deny /etc/sudoers r,
      deny /etc/sudoers.d/** r,

      # Network: HTTPS per download modelli
      network inet stream,
      network inet6 stream,
      network unix stream,
      deny network raw,
      deny network packet,

      # Capability minime
      deny capability sys_admin,
      deny capability sys_ptrace,
      deny capability dac_override,
    }
  '';
in {
  options.solem.apparmor = {
    enable = lib.mkEnableOption "AppArmor LSM + profili SOLEM (gavio-ai, ollama)";

    mode = lib.mkOption {
      type = lib.types.enum [ "complain" "enforce" ];
      default = "complain";
      description = ''
        AppArmor mode per i profili SOLEM:
          - complain: log violazioni in audit log ma non blocca (DEV)
          - enforce:  blocca davvero (PROD)
        Default complain per evitare break di GAVIO non ancora packaged.
        Passa a enforce dopo che hai validato il profilo con
        `journalctl -k | grep apparmor=DENIED`.
      '';
    };

    profileGavioAi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Carica il profilo AppArmor per il processo gavio-ai";
    };

    profileOllama = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Carica il profilo AppArmor per ollama (opt-in)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Abilita AppArmor LSM
    security.apparmor = {
      enable = true;
      killUnconfinedConfinables = false;  # NixOS quirky
      packages = with pkgs; [ apparmor-profiles ];
      policies = lib.mkMerge [
        (lib.mkIf cfg.profileGavioAi {
          "solem-gavio-ai" = {
            enable = true;
            enforce = (cfg.mode == "enforce");
            profile = gavioAiProfile;
          };
        })
        (lib.mkIf cfg.profileOllama {
          "solem-ollama" = {
            enable = true;
            enforce = (cfg.mode == "enforce");
            profile = ollamaProfile;
          };
        })
      ];
    };

    # CLI di ispezione
    environment.systemPackages = with pkgs; [
      apparmor-utils
      apparmor-bin-utils  # fornisce apparmor_parser (pkgs.apparmor-parser NON esiste)
      (pkgs.writeShellApplication {
        name = "solem-apparmor";
        runtimeInputs = with pkgs; [ coreutils apparmor-utils gnugrep ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM AppArmor ──"
              if ! command -v aa-status >/dev/null 2>&1; then
                echo "aa-status non disponibile"
                exit 1
              fi
              echo "Mode: ${cfg.mode}"
              echo
              sudo aa-status 2>&1 | grep -E "profiles|solem-" || true
              ;;

            violations|denied)
              echo "── AppArmor DENIED events (kernel log) ──"
              sudo journalctl -k --since "1 hour ago" 2>/dev/null | \
                grep "apparmor=\"DENIED\"" | tail -20 || \
                echo "(nessuna violazione, o audit non visibile)"
              ;;

            profiles)
              ls /etc/apparmor.d/ 2>/dev/null | grep -E "solem|gavio|ollama" || \
                echo "(no SOLEM profiles trovati)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-apparmor — gestione AppArmor SOLEM

  status        aa-status filtrato per profili SOLEM
  violations    DENIED events (journalctl kernel)
  profiles      list file profile in /etc/apparmor.d/

Profili attivi: ${lib.optionalString cfg.profileGavioAi "solem-gavio-ai "}${lib.optionalString cfg.profileOllama "solem-ollama"}
Mode: ${cfg.mode}

Passo a enforce dopo aver validato complain:
  1. Lascia gavio gira in mode=complain per 1 settimana
  2. solem-apparmor violations → vedi quali path sono DENIED
  3. Estendi il profilo o passa enforce se nessun DENIED legittimo
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/apparmor.md".text = ''
      # SOLEM AppArmor — MAC kernel-enforced

      ## Cosa fa

      Carica profili AppArmor per i processi AI critici:
        - solem-gavio-ai → ${aiHome}/venv/bin/python3
        - solem-ollama   → /run/current-system/sw/bin/ollama (opt-in)

      Confinamento kernel-level: anche se l'AI ottiene RCE userspace,
      AppArmor rifiuta open()/exec() di path non in policy.

      ## Mode

      ```
      solem.apparmor.mode = "complain";  # log only (default)
      # oppure
      solem.apparmor.mode = "enforce";   # block + log
      ```

      Default complain perche' GAVIO non e' ancora packaged: l'enforce
      su un profilo non testato puo' rompere GAVIO al primo avvio reale.
      Validazione: lascia 1 settimana in complain, leggi violazioni,
      estendi profilo, passa enforce.

      ## Profilo gavio-ai (riassunto)

      - Read: /usr/**, /run/current-system/**, /nix/store/**, /etc/ssl/**
      - Read+Write: ${aiHome}/**, /tmp/**, /var/tmp/**
      - Read-only: /opt/gavio/**, /etc/gavio/**
      - DENY: /home/**, /root/**, /etc/shadow, /etc/sudoers, /dev/mem,
              /sys/firmware/**, ptrace, sys_module, raw network

      ## Verifica

      ```
      solem-apparmor status      # vede profili caricati
      solem-apparmor violations  # eventi DENIED
      sudo aa-status             # output completo apparmor
      ```

      ## Limiti onesti

      - LSM kernel bypass (rari, ma CVE esistono): non protegge.
      - Profile drift: se Python upgrade cambia path venv, profile rompe.
      - "complain" mode NON blocca: serve solo per test. Devi passare a
        "enforce" per protezione reale.
      - Tutti i profili scritti a mano: pochi-stati formali verificati.
    '';
  };
}
