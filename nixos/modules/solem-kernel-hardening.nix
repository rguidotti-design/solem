{ config, pkgs, lib, ... }:

let
  cfg = config.solem.kernelHardening;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM KERNEL HARDENING — KSPP recommendations dedicato
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO kernel hardening.
  # Estende solem-secure.nix con cmdline + lockdown + KASLR + module signing.
  #
  # Riferimento: https://kspp.github.io/Recommendations/Kernel_Self_Protection_Project
  #
  # NB: bilanciato con AI freedom (ai-freedom.nix):
  # - lockdown=integrity (NON confidentiality) → permette debugger/perf per AI
  # - module signing NON forzato (AI può caricare moduli kernel custom se vuole)

  options.solem.kernelHardening = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;  # default ON
      description = "Hardening kernel KSPP completo.";
    };

    lockdown = lib.mkOption {
      type = lib.types.enum [ "none" "integrity" "confidentiality" ];
      default = "integrity";  # bilanciato con AI freedom
      description = ''
        Kernel lockdown mode:
        - none: nessun lockdown
        - integrity: protegge integrità kernel (consigliato, AI può debug)
        - confidentiality: blocca anche read kmem (più restrittivo, può rompere AI)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [
      # KSPP recommended boot parameters
      "slab_nomerge"                      # disable slab merge (use-after-free harder)
      "init_on_alloc=1"                   # zero kernel allocation
      "init_on_free=1"                    # zero kernel free
      "page_alloc.shuffle=1"              # randomize page allocator
      "pti=on"                            # Page Table Isolation (Spectre v3a)
      "vsyscall=none"                     # disable legacy vsyscall
      "debugfs=off"                       # disable /sys/kernel/debug
      "module.sig_enforce=0"              # NON enforce (AI freedom)
      "lockdown=${cfg.lockdown}"
      # KASLR aggressivo
      "kaslr"
      "kernel.kptr_restrict=2"
      # Audit
      "audit=1"
    ];

    # Disabilita filesystem rari/legacy (riduce attack surface)
    boot.blacklistedKernelModules = [
      "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs"
      "udf" "dccp" "sctp" "rds" "tipc"
      "n-hdlc" "ax25" "netrom" "x25" "rose" "decnet"
      "econet" "af_802154" "ipx" "appletalk" "psnap" "p8023" "p8022"
      # Disable bluetooth a livello kernel (riabilitato selettivamente da solem-desktop)
      # "bluetooth"
    ];

    # Manifest leggibile
    environment.etc."solem/kernel-hardening.json".text = builtins.toJSON {
      enabled = cfg.enable;
      lockdown = cfg.lockdown;
      kspp_params = [
        "slab_nomerge" "init_on_alloc=1" "init_on_free=1"
        "page_alloc.shuffle=1" "pti=on" "vsyscall=none" "debugfs=off"
        "kaslr" "audit=1" "lockdown=${cfg.lockdown}"
      ];
      blacklisted_modules_count = 25;
      note = "Bilanciato con ai-freedom.nix: lockdown=integrity, no module.sig_enforce";
    };
  };
}
