{ config, pkgs, lib, ... }:

# SOLEM HARDWARE FIRMWARE — risponde WEAKNESSES.md GRAVE #1 "Hardware OOTB".
#
# Single responsibility: SOLO abilitare il maggior numero di driver/firmware
# (FOSS-only di default, vendor blob opt-in con consenso esplicito).
#
# Cosa abilita:
# - linux-firmware FOSS (Intel/AMD/Mediatek Wi-Fi/BT redistribuibile)
# - microcode CPU updates (Intel + AMD)
# - drm/kernel modules per GPU (Intel/AMD mainline, NVIDIA opt-in)
# - bluez full Bluetooth (con A2DP/HFP audio)
# - sane scanner support
# - fwupd update firmware UEFI/BIOS via LVFS (no vendor tool)
# - iio-sensor-proxy (accelerometer, ambient light)
# - power-profiles-daemon (default Linux laptop)
#
# 0 €. Tutto FOSS o redistribuibile senza accordi vendor.

let
  cfg = config.solem.hardwareFirmware;
in {
  options.solem.hardwareFirmware = {
    enable = lib.mkEnableOption "Driver + firmware OOTB (Intel/AMD/NVIDIA/sensor/Bluetooth)";

    cpuVendor = lib.mkOption {
      type = lib.types.enum [ "intel" "amd" "auto" ];
      default = "auto";
      description = "CPU vendor per abilitare il microcode corretto. 'auto' attiva entrambi.";
    };

    nonFreeFirmware = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita firmware vendor non-FOSS (Broadcom Wi-Fi, alcuni chip Realtek).
        Off di default per coerenza FOSS. Attiva solo se Wi-Fi non funziona.
      '';
    };

    nvidia = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Driver NVIDIA proprietario (richiede chip NVIDIA). Off default.";
    };

    fwupd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "fwupd — update firmware UEFI/BIOS/SSD via LVFS (FOSS)";
    };

    bluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bluetooth completo (bluez + A2DP audio + HFP per cuffie)";
    };

    sensors = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "iio-sensor-proxy (auto-rotate tablet, ambient light brightness)";
    };

    scanner = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "SANE — scanner USB (HP/Canon/Epson/Brother)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ── Base: firmware FOSS + kernel modules ──────────────────────────
    {
      # Firmware redistribuibile (Intel Wi-Fi/Bluetooth, AMD GPU, Mediatek, ecc.)
      hardware.enableRedistributableFirmware = true;

      # Firmware completo (incluso non-FOSS) solo se l'utente lo chiede
      hardware.enableAllFirmware = lib.mkIf cfg.nonFreeFirmware true;

      # Update firmware via LVFS (UEFI/SSD/dock USB-C)
      services.fwupd.enable = cfg.fwupd;

      # Permetti unfree se utente ha attivato nvidia o nonFreeFirmware
      nixpkgs.config.allowUnfree = lib.mkIf (cfg.nvidia || cfg.nonFreeFirmware) true;
    }

    # ── CPU Microcode ─────────────────────────────────────────────────
    (lib.mkIf (cfg.cpuVendor == "intel" || cfg.cpuVendor == "auto") {
      hardware.cpu.intel.updateMicrocode = true;
    })
    (lib.mkIf (cfg.cpuVendor == "amd" || cfg.cpuVendor == "auto") {
      hardware.cpu.amd.updateMicrocode = true;
    })

    # ── Bluetooth ─────────────────────────────────────────────────────
    (lib.mkIf cfg.bluetooth {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General = {
            Enable = "Source,Sink,Media,Socket";     # A2DP audio
            Experimental = true;                     # Per LE Audio + battery indicator
          };
        };
      };
      services.blueman.enable = true;                # GUI Bluetooth
    })

    # ── Sensori (auto-rotate, brightness, accel) ──────────────────────
    (lib.mkIf cfg.sensors {
      hardware.sensor.iio.enable = true;
    })

    # ── Scanner SANE ──────────────────────────────────────────────────
    (lib.mkIf cfg.scanner {
      hardware.sane = {
        enable = true;
        extraBackends = with pkgs; [ sane-airscan ];   # AirScan/eSCL wireless
      };
      services.udev.packages = [ pkgs.sane-airscan ];
    })

    # ── NVIDIA (opt-in, closed-source) ────────────────────────────────
    (lib.mkIf cfg.nvidia {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = false;     # opt-in al closed driver
        nvidiaSettings = true;
      };
    })

    # ── Pacchetti GUI per gestione hardware ──────────────────────────
    {
      environment.systemPackages = with pkgs; [
        usbutils       # lsusb
        pciutils       # lspci
        dmidecode      # info HW BIOS
        smartmontools  # SMART SSD
        ethtool        # network ethernet
        iw             # wireless info
        lshw           # hardware listing completo
      ];
    }
  ]);
}
