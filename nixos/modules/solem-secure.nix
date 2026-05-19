{ config, pkgs, lib, ... }:

let
  cfg = config.solem.secure;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM SECURE — hardening production-grade
  # ──────────────────────────────────────────────────────────────────────
  # 5 layer di sicurezza, indipendenti tra loro (attivabili separatamente):
  #
  #   1. DISK ENCRYPTION (LUKS2)       — disk a riposo cifrato
  #   2. SECURE BOOT (Lanzaboote)      — boot integrity con chiavi firmate
  #   3. SECRET MANAGEMENT (sops-nix)  — secret cifrati nel repo, decifrati al boot
  #   4. KERNEL HARDENING              — sysctl + ASLR + ptrace restrict
  #   5. APPARMOR SELETTIVO            — profili MAC per app non-core (L7 extensions)
  #
  # Filosofia: SOLEM resta AI-native (vedi ai-freedom.nix → l'AI ha sudo,
  # polkit aperto, no MAC sui processi core). Questo modulo aggiunge confini
  # DOVE servono: disco, boot, secret, kernel, extension di terze parti.
  #
  # Tutto OPT-IN: VM di test resta semplice; produzione bare-metal attiva
  # solem.secure.*.enable = true individualmente.

  options.solem.secure = {
    diskEncryption.enable = lib.mkEnableOption "LUKS encryption (richiede setup install)";

    secureBoot.enable = lib.mkEnableOption "Secure Boot via Lanzaboote (UEFI + chiavi)";

    sopsNix = {
      enable = lib.mkEnableOption "Secret management dichiarativo (sops-nix)";
      ageKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/sops-nix/key.txt";
        description = "Path chiave age per decifrare secret.";
      };
    };

    kernelHardening.enable = lib.mkEnableOption "Kernel hardening (sysctl strict)" // {
      default = true;  # attivo di default — non rompe nulla
    };

    apparmor = {
      enable = lib.mkEnableOption "AppArmor selettivo per L7 extensions";
      profiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Profili AppArmor extra (nome → file path).";
      };
    };
  };

  config = lib.mkMerge [
    # ── 1. DISK ENCRYPTION (LUKS2) ──────────────────────────────────
    (lib.mkIf cfg.diskEncryption.enable {
      # Setup richiede installazione manuale: vedi docs/INSTALL_BAREMETAL.md
      # Esempio fileSystems entry per root cifrata:
      #   boot.initrd.luks.devices."cryptroot" = {
      #     device = "/dev/disk/by-uuid/<UUID>";
      #     allowDiscards = true;     # SSD trim
      #     bypassWorkqueues = true;  # performance NVMe
      #   };
      #   fileSystems."/" = { device = "/dev/mapper/cryptroot"; fsType = "ext4"; };
      #
      # In Step 1+ (bare-metal Beelink): config completa qui.
      assertions = [{
        assertion = false;
        message = ''
          solem.secure.diskEncryption.enable richiede config LUKS specifica
          dell'hardware. Vedi docs/INSTALL_BAREMETAL.md per setup completo
          (UUID disco, partition layout, header backup).
        '';
      }];
    })

    # ── 2. SECURE BOOT (Lanzaboote) ────────────────────────────────
    (lib.mkIf cfg.secureBoot.enable {
      # Lanzaboote sostituisce GRUB con stub UEFI firmato.
      # Setup: 1) systemd-boot 2) generare chiavi 3) lanzaboote enable
      # NB: richiede flake input "lanzaboote.url = github:nix-community/lanzaboote"
      # (non incluso di default, da aggiungere in flake.nix quando si attiva).
      boot.loader.systemd-boot.enable = lib.mkForce false;  # sostituito da lanzaboote
      assertions = [{
        assertion = false;
        message = ''
          solem.secure.secureBoot.enable richiede l'input "lanzaboote" nel flake
          e generazione chiavi via sbctl. Vedi docs/SECURE_BOOT.md (Step 1+).
        '';
      }];
    })

    # ── 3. SECRET MANAGEMENT (sops-nix) ────────────────────────────
    (lib.mkIf cfg.sopsNix.enable {
      # sops-nix: i secret .yaml/.json cifrati con age stanno nel repo,
      # decifrati al boot con la chiave age del nodo (mai in git).
      #
      # File esempio (secrets/gavio.yaml cifrato age):
      #   GROQ_API_KEY: ENC[AES256_GCM,data:...,iv:...,tag:...]
      #   SUPABASE_SERVICE_KEY: ENC[...]
      #
      # Decrypted runtime in /run/secrets/<name>, gid:uid configurabili.
      assertions = [{
        assertion = false;
        message = ''
          solem.secure.sopsNix.enable richiede input "sops-nix" nel flake + chiave
          age in ${cfg.sopsNix.ageKeyFile}. Vedi docs/SECRETS.md (Step 1+).
        '';
      }];
    })

    # ── 4. KERNEL HARDENING (sysctl strict, ASLR, ptrace) ──────────
    # Attivo di default — best practice senza romper niente.
    (lib.mkIf cfg.kernelHardening.enable {
      boot.kernel.sysctl = {
        # Network hardening
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.all.accept_redirects" = 0;

        # Kernel hardening
        "kernel.kptr_restrict" = 2;        # nascondi puntatori kernel
        "kernel.dmesg_restrict" = 1;       # solo root legge dmesg
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;
        "kernel.yama.ptrace_scope" = 1;    # ptrace solo child/CAP_SYS_PTRACE

        # File system
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;
        "fs.suid_dumpable" = 0;            # no core dump per binary SUID
      };

      # ASLR sempre attivo (default ma esplicito)
      security.allowSimultaneousMultithreading = true;

      # Disabilita filesystem rari/legacy come modulo (riduci superficie)
      boot.blacklistedKernelModules = [
        "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs"
        "udf" "dccp" "sctp" "rds" "tipc"  # protocolli rete legacy
      ];
    })

    # ── 5. APPARMOR SELETTIVO (L7 extensions sandboxing) ───────────
    (lib.mkIf cfg.apparmor.enable {
      security.apparmor = {
        enable = true;
        killUnconfinedConfinables = false;  # NON killare app non-confinate
        # Profili custom: applicati a binari specifici delle extensions L7
        policies = lib.mapAttrs (name: path: {
          enable = true;
          profile = builtins.readFile path;
        }) cfg.apparmor.profiles;
      };
      # NB: i processi del CORE SOLEM (gavio, solem-api, ollama) restano
      # NON confinati (vedi ai-freedom.nix). Solo extensions L7 caricano profili.
    })
  ];
}
