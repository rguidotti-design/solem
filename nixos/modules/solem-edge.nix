{ config, pkgs, lib, ... }:

# SOLEM EDGE — profilo ottimizzato per device low-power (Raspberry/Jetson/SBC).
#
# Single responsibility: SOLO tuning per device piccoli:
#   - ZRAM 2× RAM (no swap su SD)
#   - Journal volatile (RAM only) per preservare la SD
#   - Niente cron pesanti (no nix-gc oltre 7 giorni)
#   - Niente desktop, niente Ollama default
#   - Watchdog kernel (reboot se hang per 30s)

let
  cfg = config.solem.edge;
in {
  options.solem.edge = {
    enable = lib.mkEnableOption "Profilo edge low-power (ZRAM + journal RAM + watchdog)";

    deviceClass = lib.mkOption {
      type = lib.types.enum [ "edge-cpu" "edge-gpu" "iot" "glass-companion" ];
      default = "edge-cpu";
      description = ''
        edge-cpu  → Raspberry Pi headless, mini-NAS
        edge-gpu  → Jetson Nano/Orin (CUDA Tegra)
        iot       → device GPIO/sensor (Raspberry Pi Pico/Zero)
        glass-companion → relay verso smart glasses (mini box)
      '';
    };

    enableSwap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disabilita swap fisico (preserva SD card)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── ZRAM al posto di swap su disco ───
    zramSwap = {
      enable = true;
      memoryPercent = 100;       # ZRAM = 100% RAM (LZ4 ratio ~2.5×)
      algorithm = "zstd";
    };

    # ─── Niente swap su SD card (logora la flash) ───
    swapDevices = lib.mkForce [];

    # ─── Journal in RAM (volatile) ───
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=50M
      SystemMaxUse=0
    '';

    # ─── Disabilita systemd-timer pesanti su edge ───
    services.fstrim.enable = false;  # SD non beneficia da TRIM
    services.fwupd.enable = false;   # No firmware update auto
    services.timesyncd.enable = true;  # solo NTP leggero

    # ─── Watchdog hardware/kernel ───
    systemd.watchdog = {
      runtimeTime = "30s";
      rebootTime = "5min";
    };

    # ─── No desktop, no Ollama in default su edge ───
    services.xserver.enable = lib.mkDefault false;

    # ─── Kernel tuning per low-RAM ───
    boot.kernel.sysctl = {
      "vm.swappiness" = 10;           # usa ZRAM presto
      "vm.vfs_cache_pressure" = 200;  # rilascia cache rapidamente
      "vm.dirty_ratio" = 5;
      "vm.dirty_background_ratio" = 2;
      "net.ipv4.tcp_keepalive_time" = 60;
    };

    # ─── Cluster: registra come edge worker ───
    solem.cluster.deviceName = lib.mkDefault config.networking.hostName;

    # ─── Banner che indica device class ───
    environment.etc."solem/edge-class".text = cfg.deviceClass;

    # ─── Tag aggiuntivo: env per heartbeat cluster ───
    environment.sessionVariables = {
      SOLEM_DEVICE_CLASS = cfg.deviceClass;
    };
  };
}
