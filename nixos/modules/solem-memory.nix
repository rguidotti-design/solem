{ config, pkgs, lib, ... }:

let
  cfg = config.solem.memory;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM MEMORY — zram + earlyoom + systemd-oomd
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO gestione memoria per workload AI.
  # Allineamento Prompt Master v4.0 sez. 1.3.
  #
  # Strategia:
  #   1. zram swap (compresso in RAM) → no swap su disco → veloce + privacy
  #   2. earlyoom → uccide processi quando RAM critica PRIMA del kernel OOM
  #   3. systemd-oomd → policy avanzate per-cgroup (preserva gavio.service)

  options.solem.memory = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Memory management per workload AI (zram + earlyoom + oomd).";
    };

    zramSize = lib.mkOption {
      type = lib.types.str;
      default = "50%";
      description = "Size zram swap (% di RAM fisica).";
    };

    hugePages = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Numero huge pages 2MB. 0 = disabled. 1024 = 2GB riservati per LLM.";
    };

    protectGavio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "earlyoom/oomd evitano di uccidere gavio.service / ollama.service / solem-api.service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # zram swap
    zramSwap = {
      enable = true;
      memoryPercent = lib.toInt (lib.removeSuffix "%" cfg.zramSize);
      algorithm = "zstd";   # migliore compressione
    };

    # earlyoom (kernel-level fast OOM killer)
    services.earlyoom = {
      enable = true;
      freeMemThreshold = 5;     # %, kill quando free RAM < 5%
      freeSwapThreshold = 10;   # %
      enableNotifications = true;
      # Preferisci kill di processi che NON sono SOLEM core
      extraArgs = lib.optionals cfg.protectGavio [
        "--prefer" "^(chromium|firefox|electron|node|java)$"
        "--avoid" "^(systemd|systemd-journald|sshd|gaviod|ollama|solem-api)$"
      ];
    };

    # systemd-oomd (userspace, policy granulare)
    systemd.oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
      enableSystemSlice = false;  # NON applicare a system.slice (gavio/ollama protetti)
    };

    # Huge pages opt-in (allocazione statica)
    boot.kernel.sysctl = lib.mkIf (cfg.hugePages > 0) {
      "vm.nr_hugepages" = cfg.hugePages;
    };

    # MemoryHigh per gavio.service: hint allocazione (no kill).
    # Applicato SOLO se il servizio gavio esiste (cfg.protectGavio + import).
    # Senza questo guard, configuration-vm-minimal creerebbe un gavio.service
    # vuoto che fallirebbe al boot.
    systemd.services.gavio.serviceConfig = lib.mkIf cfg.protectGavio {
      MemoryHigh = "3G";
      MemoryMax = lib.mkForce "4G";
      MemorySwapMax = "1G";
    };

    environment.etc."solem/memory-config.json".text = builtins.toJSON {
      zram = "${cfg.zramSize} zstd";
      earlyoom = "free_mem<5% free_swap<10%";
      systemd_oomd = "user_slices=true system_slice=false";
      huge_pages = cfg.hugePages;
      gavio_protected = cfg.protectGavio;
    };
  };
}
