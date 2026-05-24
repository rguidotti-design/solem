{ config, pkgs, lib, ... }:

# SOLEM KERNEL HARDEN — sysctl strict + lockdown + module restrictions.
#
# Single responsibility: SOLO tuning kernel-level enforced (sysctl,
# boot params, module loading). Non tocca firewall (vedi solem-ai-network),
# non tocca filesystem (vedi solem-encrypted-memory).
#
# Chiude vettori di attacco kernel-level reali, CVE storici noti:
#   - unprivileged BPF (CVE-2022-23222, CVE-2021-3490, ecc.)
#   - unprivileged user namespaces (CVE-2022-0492, CVE-2018-18955)
#   - ptrace cross-user (info leak credentials altri processi)
#   - kptr leak (KASLR bypass)
#   - kexec (load unsigned kernel)
#   - module loading post-boot (rootkit kernel modules)
#   - SUID core dumps (info leak)
#   - SYN flood, ICMP redirect, source routing
#
# Tutto FOSS, native Linux kernel. 0 €.

let
  cfg = config.solem.kernelHarden;
in {
  options.solem.kernelHarden = {
    enable = lib.mkEnableOption "Kernel hardening strict (sysctl + lockdown + modules)";

    lockdownMode = lib.mkOption {
      type = lib.types.enum [ "none" "integrity" "confidentiality" ];
      default = "integrity";
      description = ''
        Kernel lockdown LSM mode:
          - none:           nessuno (default upstream)
          - integrity:      blocca modifiche al kernel running (raccomandato)
          - confidentiality: blocca anche READ di kernel memory (piu' restrittivo)
        confidentiality puo' rompere alcuni debug tools — usa integrity di default.
      '';
    };

    disableModuleLoading = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        kernel.modules_disabled=1 dopo boot: NESSUN kernel module puo'
        essere caricato/scaricato dopo l'avvio. Estremamente restrittivo:
        plug & play USB driver, nvidia driver dinamici, ecc. NON funzionano.
        Default off; abilita su server / sistemi statici.
      '';
    };

    disableUserNamespaces = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Disabilita user namespaces non privilegiati.
        IMPATTO: rootless docker/podman NON funziona, alcuni sandbox
        (chromium namespace, bubblewrap senza --userns) si rompono.
        Mitiga: CVE-2022-0492, CVE-2018-18955, lateral movement.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # 1. sysctl: filesystem + kernel + networking
    # ────────────────────────────────────────────────────────────────
    boot.kernel.sysctl = {
      # ── Kernel info leak protection ────────────────────────────
      # Nasconde indirizzi kernel da /proc/kallsyms e simili.
      # Anti-KASLR bypass.
      "kernel.kptr_restrict" = 2;

      # Blocca dmesg per utenti non-root.
      "kernel.dmesg_restrict" = 1;

      # ── Ptrace: solo parent->child (no peer-to-peer) ───────────
      # 0 = classic (qualsiasi processo stesso UID)
      # 1 = solo parent->child (yama default)
      # 2 = solo CAP_SYS_PTRACE (admin)
      # 3 = ptrace disabled completely
      "kernel.yama.ptrace_scope" = 2;

      # ── kexec disabled ─────────────────────────────────────────
      # Impedisce di caricare un nuovo kernel via kexec.
      # Senza questo, root puo' caricare un kernel arbitrario (no Secure Boot).
      "kernel.kexec_load_disabled" = 1;

      # ── BPF unprivileged disabilitato ──────────────────────────
      # BPF e' una superficie di attacco storica (>30 CVE 2018-2024).
      # Solo root puo' load BPF programs.
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;

      # ── core dump SUID ─────────────────────────────────────────
      # 0 = core dump di processi SUID disabled.
      # Anti info-leak (un attacker forza un crash di un SUID per
      # estrarre memoria da /proc/PID/coredump).
      "fs.suid_dumpable" = 0;

      # ── Filesystem protection ──────────────────────────────────
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;
      "fs.protected_fifos" = 2;       # 2 = world-writable e other dir
      "fs.protected_regular" = 2;

      # ── perf events disabilitati per non-root ──────────────────
      # perf_event_open() ha avuto multiple CVE (CVE-2013-2094 storico).
      # 3 = solo CAP_SYS_ADMIN
      "kernel.perf_event_paranoid" = 3;

      # ── Networking strict ──────────────────────────────────────
      # SYN flood protection
      "net.ipv4.tcp_syncookies" = 1;

      # No source routing (anti spoofing)
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      # No ICMP redirects (anti MITM)
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      # Non inviare redirect (non siamo router)
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;

      # Reverse path filtering (anti spoofing)
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;

      # Log pacchetti con martian source (illegal source addr)
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;

      # Ignora ICMP broadcast (anti smurf)
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # IPv4 forwarding off (non siamo router/VPN gateway)
      "net.ipv4.ip_forward" = lib.mkDefault 0;

      # TCP timestamp off (info leak su uptime)
      "net.ipv4.tcp_timestamps" = 0;
    };

    # ────────────────────────────────────────────────────────────────
    # 2. User namespaces: opzionale (rompe sandbox userspace)
    # `user.max_user_namespaces=0` e' upstream standard, disabilita
    # la creazione di nuovi user namespace (anche per root).
    # NB: `kernel.unprivileged_userns_clone` esiste solo con patch Debian.
    # ────────────────────────────────────────────────────────────────
    boot.kernel.sysctl."user.max_user_namespaces" = lib.mkIf cfg.disableUserNamespaces 0;

    # ────────────────────────────────────────────────────────────────
    # 3. Module loading lock dopo boot (opzionale, hardware statico)
    # ────────────────────────────────────────────────────────────────
    boot.kernel.sysctl."kernel.modules_disabled" = lib.mkIf cfg.disableModuleLoading 1;

    # ────────────────────────────────────────────────────────────────
    # 4. Kernel lockdown LSM (boot param)
    # ────────────────────────────────────────────────────────────────
    boot.kernelParams = lib.optionals (cfg.lockdownMode != "none") [
      "lockdown=${cfg.lockdownMode}"

      # Slab freelist randomization (anti heap exploit)
      "slab_nomerge"
      "init_on_alloc=1"
      "init_on_free=1"

      # Page poisoning (anti use-after-free info leak)
      "page_poison=1"

      # Vsyscall: emulate (no exec direct, anti ROP gadget gratuito)
      "vsyscall=none"

      # Disable Intel ME if present
      # mce=0 disabilitato perche' utile su prod
    ];

    # ────────────────────────────────────────────────────────────────
    # 5. Core dumps disabled
    # ────────────────────────────────────────────────────────────────
    systemd.coredump.enable = lib.mkDefault false;
    security.pam.loginLimits = [
      { domain = "*"; type = "hard"; item = "core"; value = "0"; }
      { domain = "*"; type = "soft"; item = "core"; value = "0"; }
    ];

    # ────────────────────────────────────────────────────────────────
    # 6. Disable blacklisted kernel modules vulnerabili / obsoleti
    # ────────────────────────────────────────────────────────────────
    boot.blacklistedKernelModules = [
      # Filesystem obsoleti (storia di CVE)
      "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
      # Network protocols obsoleti
      "dccp" "sctp" "rds" "tipc"
      # FireWire (DMA attack vector)
      "firewire-core" "firewire-ohci" "firewire-sbp2"
      # Floppy (storico, niente di buono)
      "floppy"
    ];

    # ────────────────────────────────────────────────────────────────
    # 7. CLI di ispezione
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-kernel-check";
        runtimeInputs = with pkgs; [ coreutils gnugrep procps ];
        text = ''
          echo "── SOLEM Kernel Harden — verifica sysctl ──"
          echo

          check() {
            local KEY="$1"
            local EXPECTED="$2"
            local ACTUAL
            ACTUAL=$(sysctl -n "$KEY" 2>/dev/null || echo "MISSING")
            if [ "$ACTUAL" = "$EXPECTED" ]; then
              printf "  ✓ %-45s = %s\n" "$KEY" "$ACTUAL"
            else
              printf "  ✗ %-45s = %s (atteso %s)\n" "$KEY" "$ACTUAL" "$EXPECTED"
            fi
          }

          check kernel.kptr_restrict 2
          check kernel.dmesg_restrict 1
          check kernel.yama.ptrace_scope 2
          check kernel.kexec_load_disabled 1
          check kernel.unprivileged_bpf_disabled 1
          check kernel.perf_event_paranoid 3
          check fs.suid_dumpable 0
          check fs.protected_hardlinks 1
          check fs.protected_symlinks 1
          check net.ipv4.tcp_syncookies 1
          check net.ipv4.conf.all.rp_filter 1
          check net.ipv4.conf.all.accept_redirects 0
          check net.ipv4.conf.all.accept_source_route 0

          echo
          echo "── Lockdown mode ──"
          cat /sys/kernel/security/lockdown 2>/dev/null || echo "(no lockdown LSM)"

          echo
          echo "── Blacklisted modules attivi? ──"
          for M in cramfs freevxfs dccp rds tipc firewire-core floppy; do
            if lsmod 2>/dev/null | grep -q "^$M"; then
              echo "  ✗ $M CARICATO (NON dovrebbe)"
            else
              echo "  ✓ $M non caricato"
            fi
          done
        '';
      })
    ];

    environment.etc."solem/kernel-harden.md".text = ''
      # SOLEM Kernel Harden

      ## Cosa fa

      Applica sysctl strict + boot params hardening + module blacklist
      contro vettori di attacco kernel-level documentati:

        - kptr_restrict=2 → no leak indirizzi kernel
        - yama.ptrace_scope=2 → no ptrace cross-user
        - kexec_load_disabled=1 → no kernel runtime swap
        - unprivileged_bpf_disabled=1 → BPF solo root (>30 CVE storici)
        - perf_event_paranoid=3 → perf_event_open solo CAP_SYS_ADMIN
        - lockdown=${cfg.lockdownMode} → MAC restriction su modify/inspect kernel
        - blacklist cramfs/dccp/firewire/floppy/... → no superficie attacco

      ## Boot params aggiunti

        - slab_nomerge          (no slab merge, anti heap exploit)
        - init_on_alloc=1       (memoria zeroizzata su alloc)
        - init_on_free=1        (memoria zeroizzata su free)
        - page_poison=1         (page poisoning, anti UAF leak)
        - vsyscall=none         (no syscall via vsyscall, anti ROP)

      ## Compatibilita'

      Cose che POTREBBERO non funzionare con questa config:
        - rootless container (userns disabled): docker --userns-remap richiesto
        - bubblewrap senza --userns-namespace
        - chromium sandbox userspace
        - kernel debug live (perf, kexec disabled)
        - kernel driver dinamici (se disableModuleLoading=true)

      Soluzione: solem.kernelHarden.disableUserNamespaces = false; se serve
      qualcuno di questi. Trade-off security vs functionality.

      ## Limiti onesti

      - Non protegge da exploit kernel zero-day non mitigati dai flag.
      - lockdown=integrity NON blocca read di kernel memory (per quello
        serve confidentiality, ma rompe perf debug).
      - Non rimpiazza Secure Boot + TPM measured boot.
    '';
  };
}
