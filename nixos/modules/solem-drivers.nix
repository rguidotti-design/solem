{ config, pkgs, lib, ... }:

# SOLEM DRIVERS — gestione driver e firmware (NVIDIA + WiFi + audio).
#
# Single responsibility: SOLO config dei driver hardware. Niente
# detection runtime (è hardware_detect.py).
#
# Filosofia: FOSS by default, proprietari opt-in.
#   - Linux firmware (iwlwifi, rtl, brcm): incluso default (LGPL+)
#   - NVIDIA proprietary: opt-in via solem.drivers.nvidia.enable
#   - AMD ROCm: opt-in (community kernel module)
#   - Intel iGPU: incluso (mesa)

let
  cfg = config.solem.drivers;
in {
  options.solem.drivers = {
    nvidia = {
      enable = lib.mkEnableOption "Driver NVIDIA proprietario (closed-source, opt-in)";
      open = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Usa kernel module open-source (GeForce 20+ supportato)";
      };
      powerManagement = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Power management D-Bus (utile su laptop hybrid graphics)";
      };
    };

    amdgpu = {
      enable = lib.mkEnableOption "AMD GPU (radeon/amdgpu mesa)";
      rocm = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "ROCm runtime (CUDA-alike) per inference su AMD";
      };
    };

    intel = {
      enable = lib.mkEnableOption "Intel iGPU + CPU microcode";
    };

    wifi = {
      includeProprietary = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Includi firmware proprietario WiFi (Intel iwlwifi, Broadcom, Realtek)";
      };
    };

    bluetooth = lib.mkEnableOption "Bluetooth (bluez + firmware)";

    printer = lib.mkEnableOption "CUPS + driver stampante (HP, Brother, Canon, Epson)";

    scanner = lib.mkEnableOption "SANE + driver scanner";

    fingerprint = lib.mkEnableOption "fprintd (lettore impronte digitali)";
  };

  config = lib.mkMerge [
    # ── NVIDIA ──
    (lib.mkIf cfg.nvidia.enable {
      nixpkgs.config.allowUnfree = true;
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = true;
        open = cfg.nvidia.open;
        nvidiaSettings = true;
        powerManagement.enable = cfg.nvidia.powerManagement;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
    })

    # ── AMD ──
    (lib.mkIf cfg.amdgpu.enable {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          amdvlk
          rocmPackages.clr-icd
        ] ++ lib.optionals cfg.amdgpu.rocm [
          rocmPackages.rocm-runtime
          rocmPackages.rocminfo
        ];
      };
    })

    # ── Intel ──
    (lib.mkIf cfg.intel.enable {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-compute-runtime
        ];
      };
      hardware.cpu.intel.updateMicrocode = true;
    })

    # ── WiFi firmware ──
    (lib.mkIf cfg.wifi.includeProprietary {
      hardware.enableRedistributableFirmware = true;
      hardware.firmware = with pkgs; [
        linux-firmware    # Intel iwlwifi, Realtek, Broadcom
      ];
    })

    # ── Bluetooth ──
    (lib.mkIf cfg.bluetooth {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
      services.blueman.enable = true;
    })

    # ── Printer ──
    (lib.mkIf cfg.printer {
      services.printing = {
        enable = true;
        drivers = with pkgs; [
          gutenprint hplip brlaser brgenml1lpr cnijfilter2
        ];
      };
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };
    })

    # ── Scanner ──
    (lib.mkIf cfg.scanner {
      hardware.sane = {
        enable = true;
        extraBackends = with pkgs; [ hplipWithPlugin ];
      };
      users.users.gavio.extraGroups = lib.mkAfter [ "scanner" "lp" ];
    })

    # ── Fingerprint ──
    (lib.mkIf cfg.fingerprint {
      services.fprintd.enable = true;
    })
  ];
}
