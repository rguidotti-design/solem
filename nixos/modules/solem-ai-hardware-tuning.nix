{ config, pkgs, lib, ... }:

# SOLEM AI HARDWARE TUNING — il computer è ottimizzato per far girare GAVIO.
#
# Single responsibility: SOLO tuning kernel/sysctl/cgroup/scheduler per
# inference AI. Niente install LLM (è in ollama service).
#
# Ottimizzazioni:
#   - Transparent HugePages always (Ollama mmap modelli ~GB)
#   - vm.swappiness=1 (no swap aggressivo, conserva RAM per modelli)
#   - vm.overcommit_memory=1 (Ollama alloca grandi blocchi)
#   - MGLRU se kernel ≥6.1 (better page reclaim per LLM working set)
#   - CPU governor "performance" su core dedicati a Ollama
#   - CPU pinning ollama.service su core fisici (no SMT siblings)
#   - I/O scheduler "none" su NVMe (riduce latency)
#   - Network buffer grandi (per Ollama streaming + GAVIO API multi-client)
#   - GPU passthrough scaffold (NVIDIA + AMD ROCm + Intel)
#   - tmpfs grandi per /tmp (Ollama scratch)

let
  cfg = config.solem.aiHardwareTuning;
in {
  options.solem.aiHardwareTuning = {
    enable = lib.mkEnableOption "Tuning hardware per inference AI (Ollama/GAVIO)";

    ollamaCores = lib.mkOption {
      type = lib.types.str;
      default = "2-7";
      description = "CPU cores dedicati a Ollama (cset format, es. '2-7' o '0,2,4,6')";
    };

    gpu = lib.mkOption {
      type = lib.types.enum [ "none" "nvidia" "amd" "intel" ];
      default = "none";
      description = "GPU per accelerazione inference (Ollama / llama.cpp)";
    };

    hugePagesGB = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "GB di HugePages 2MB pre-allocate (0 = disabilitato)";
    };

    transparentHugepages = lib.mkOption {
      type = lib.types.enum [ "always" "madvise" "never" ];
      default = "always";
      description = "THP — 'always' per LLM (più TLB hit), 'madvise' per misto";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Kernel sysctl per AI workload ──
    boot.kernel.sysctl = {
      "vm.swappiness" = 1;
      "vm.overcommit_memory" = 1;       # Ollama alloca grandi blocchi
      "vm.max_map_count" = 1048576;     # mmap di tanti file modello
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 3;
      "vm.vfs_cache_pressure" = 50;     # tieni cache LLM in RAM

      # Network buffers (GAVIO multi-client streaming)
      "net.core.rmem_max" = 268435456;  # 256 MB
      "net.core.wmem_max" = 268435456;
      "net.core.netdev_max_backlog" = 16384;
      "net.ipv4.tcp_rmem" = "4096 87380 268435456";
      "net.ipv4.tcp_wmem" = "4096 65536 268435456";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.default_qdisc" = "fq";

      # File descriptors (Ollama + GAVIO + selfhost = tanti open file)
      "fs.file-max" = 2097152;
      "fs.inotify.max_user_watches" = 524288;
    };

    # ── Kernel cmdline ──
    boot.kernelParams = [
      "transparent_hugepage=${cfg.transparentHugepages}"
      "mitigations=auto"                # NON disabilitiamo mitigations (sicurezza)
      "iommu=pt"                         # IOMMU passthrough per GPU
      "intel_iommu=on"
      "amd_iommu=on"
    ] ++ lib.optional (cfg.hugePagesGB > 0) "hugepages=${toString (cfg.hugePagesGB * 512)}";

    # ── CPU governor performance ──
    powerManagement.cpuFreqGovernor = lib.mkForce "performance";

    # ── I/O scheduler ottimizzato per NVMe ──
    services.udev.extraRules = ''
      # NVMe: niente scheduler (latency-critical)
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
      # SATA SSD: mq-deadline
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
      # HDD rotante: bfq (fair)
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
    '';

    # ── CPU pinning Ollama (riserva core a inference) ──
    systemd.services.ollama = {
      serviceConfig = {
        CPUAffinity = cfg.ollamaCores;
        Nice = -5;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
        # Niente memory limit: Ollama deve poter usare tutta la RAM disponibile
        MemoryMax = "infinity";
        # Disabilita OOM kill su ollama (proteggiamo l'AI)
        OOMScoreAdjust = -500;
      };
    };

    # Anche GAVIO (è il consumer principale di Ollama)
    systemd.services.gavio = lib.mkIf (config.systemd.services ? gavio) {
      serviceConfig = {
        Nice = -3;
        OOMScoreAdjust = -300;
      };
    };

    # ── GPU drivers (in base a hardware) ──
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # NVIDIA
    services.xserver.videoDrivers = lib.mkIf (cfg.gpu == "nvidia") [ "nvidia" ];
    hardware.nvidia = lib.mkIf (cfg.gpu == "nvidia") {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # AMD ROCm (per llama.cpp)
    hardware.graphics.extraPackages = lib.mkIf (cfg.gpu == "amd") (with pkgs; [
      rocmPackages.clr-icd
      rocmPackages.rocm-runtime
    ]);

    # Intel iGPU/Arc
    hardware.graphics.extraPackages = lib.mkIf (cfg.gpu == "intel") (with pkgs; [
      intel-media-driver
      vaapiIntel
      intel-compute-runtime
    ]);

    # ── tmpfs grandi per scratch AI ──
    boot.tmp.useTmpfs = true;
    boot.tmp.tmpfsSize = "50%";   # metà RAM in /tmp

    # ── Limit ulimit per gavio user ──
    security.pam.loginLimits = [
      { domain = "gavio"; type = "soft"; item = "nofile"; value = "1048576"; }
      { domain = "gavio"; type = "hard"; item = "nofile"; value = "1048576"; }
      { domain = "gavio"; type = "soft"; item = "memlock"; value = "unlimited"; }
      { domain = "gavio"; type = "hard"; item = "memlock"; value = "unlimited"; }
    ];

    # ── Pacchetti diagnostica AI ──
    environment.systemPackages = with pkgs; [
      htop btop nvtopPackages.full
      sysstat       # iostat, vmstat, mpstat
      perf-tools
      schedtool
      cpupower
    ];
  };
}
