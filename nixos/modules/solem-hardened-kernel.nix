{ config, pkgs, lib, ... }:

# SOLEM HARDENED KERNEL — usa pkgs.linuxPackages_hardened.
#
# Single responsibility: SOLO swap del kernel package a hardened.
# Non configura sysctl runtime (vedi solem-kernel-harden), non configura
# secure boot (futuro).
#
# linuxPackages_hardened applica patch compile-time che sysctl NON puo'
# replicare:
#   - KSPP recommendations baked into config
#   - CONFIG_RANDOMIZE_BASE (KASLR strict)
#   - CONFIG_RANDOMIZE_MEMORY
#   - CONFIG_STACKPROTECTOR_STRONG
#   - CONFIG_FORTIFY_SOURCE
#   - CONFIG_INIT_STACK_ALL_ZERO
#   - CONFIG_DEBUG_NOTIFIERS
#   - CONFIG_REFCOUNT_FULL
#   - CONFIG_HARDENED_USERCOPY
#   - CONFIG_SLAB_FREELIST_HARDENED + CONFIG_SLAB_FREELIST_RANDOM
#   - CONFIG_BUG_ON_DATA_CORRUPTION
#   - CONFIG_LDISC_AUTOLOAD disabled
#   - CONFIG_USERFAULTFD disabled (rmqemu attacks)
#   - CONFIG_IO_URING disabled (recent CVE)
#   - GR-PaX-style port se incluso
#
# Trade-off ONESTI:
#   - ~3-5% overhead CPU per security patch (KASLR strict, refcount full,
#     usercopy hardened).
#   - Alcuni programmi rompono: software che usa io_uring (recent FastAPI/
#     uvloop), userfaultfd (CRIU live migration), certi BPF use case.
#   - Kernel hardened release in nixpkgs e' indietro 1-2 minor version
#     rispetto a vanilla.
#   - VM driver: hardened kernel ha controlli stretti sui moduli,
#     possibile break su driver virtio non firmati. In VM nixosTest
#     funziona perche' moduli built-in.

let
  cfg = config.solem.hardenedKernel;
in {
  options.solem.hardenedKernel = {
    enable = lib.mkEnableOption ''
      Sostituisce kernel package a linuxPackages_hardened (KSPP + GRSEC port).
      Trade-off ~3-5% CPU overhead per security compile-time.
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackages_hardened;

    # CLI per verificare flag attivi
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-kernel-info";
        runtimeInputs = with pkgs; [ coreutils gnugrep gawk ];
        text = ''
          echo "── SOLEM Hardened Kernel ──"
          echo "Running: $(uname -r)"
          echo
          echo "── Config flag KSPP (estratto) ──"
          CONFIG=/proc/config.gz
          if [ -f "$CONFIG" ]; then
            zcat "$CONFIG" 2>/dev/null | grep -E "^CONFIG_(RANDOMIZE_BASE|RANDOMIZE_MEMORY|STACKPROTECTOR_STRONG|FORTIFY_SOURCE|INIT_STACK_ALL_ZERO|HARDENED_USERCOPY|SLAB_FREELIST_HARDENED|SLAB_FREELIST_RANDOM|BUG_ON_DATA_CORRUPTION|REFCOUNT_FULL|DEBUG_NOTIFIERS|GCC_PLUGIN_LATENT_ENTROPY|IO_URING|USERFAULTFD)" | head -30
          else
            echo "/proc/config.gz non disponibile (kernel built without IKCONFIG_PROC)"
            echo "Verifica indirettamente:"
            echo "  - io_uring syscall: $(zcat /proc/config.gz 2>/dev/null | grep -c IO_URING || echo unknown)"
            echo "  - userfaultfd: $(ls /proc/sys/vm/unprivileged_userfaultfd 2>/dev/null || echo absent)"
          fi
          echo
          echo "── Comparison Vanilla vs Hardened ──"
          if [[ "$(uname -r)" == *hardened* ]] || [[ "$(uname -r)" == *libre* ]]; then
            echo "✓ Sei sul kernel HARDENED"
          else
            echo "⚠ Stai usando kernel vanilla. Abilita solem.hardenedKernel.enable=true"
          fi
        '';
      })
    ];

    environment.etc."solem/hardened-kernel.md".text = ''
      # SOLEM Hardened Kernel

      Swap di `boot.kernelPackages` a `pkgs.linuxPackages_hardened`.

      ## Cosa fa
      Sostituisce il kernel Linux standard con la variant hardened
      mantenuta in nixpkgs, che include compile-time patches da:
        - KSPP (Kernel Self Protection Project) recommendations
        - GRSEC/PaX porting (parziale)
        - KSPP-style strict CONFIG defaults

      ## Differenza vs sysctl runtime (solem-kernel-harden)
      sysctl puo' configurare RUNTIME (es. kptr_restrict=2).
      Hardened kernel applica BUILD-TIME flag che sysctl non puo' fare:
        - HARDENED_USERCOPY (kernel-userspace boundary checks)
        - SLAB_FREELIST_HARDENED (anti heap exploit slab)
        - FORTIFY_SOURCE (compile-time bound check su strcpy/memcpy)
        - STACKPROTECTOR_STRONG (canary su ogni funzione con buffer)
        - REFCOUNT_FULL (overflow detection refcount)
        - BUG_ON_DATA_CORRUPTION (kernel panic invece di silent corruption)

      Da combinare con solem-kernel-harden per defense-in-depth.

      ## Verifica
      ```
      solem-kernel-info       # mostra config flag attivi
      uname -r                # deve contenere "-hardened"
      ```

      ## Trade-off
      - **Overhead**: 3-5% CPU (refcount full, usercopy hardened).
      - **Version lag**: hardened release segue 1-2 minor version
        dietro vanilla (es. 6.6.x quando vanilla e' a 6.8.x).
      - **io_uring disabled**: applicazioni che usano io_uring (recente
        FastAPI con uvloop, alcuni async I/O moderni) potrebbero rompersi.
        Fallback: usa kernel vanilla per quei carichi specifici.
      - **userfaultfd disabled**: CRIU live migration non funziona.
      - **BPF unprivileged**: gia' coperto da sysctl ma hardened lo fa
        anche compile-time (doppia protezione).

      ## Limiti onesti
      - NON e' grsecurity vero (che e' chiuso). E' un porting parziale.
      - Hardened release dipende dal maintainer nixpkgs: se rilascio
        si ferma per CVE upstream, il sistema resta su kernel vecchio.
      - Non sostituisce Secure Boot + TPM measured boot.
    '';
  };
}
