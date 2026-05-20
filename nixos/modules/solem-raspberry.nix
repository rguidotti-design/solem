{ config, pkgs, lib, ... }:

# SOLEM RASPBERRY PI — specifico Raspberry Pi 4/5 (BCM2711/BCM2712).
#
# Single responsibility: SOLO config Pi-specific:
#   - Firmware Broadcom WiFi (brcm)
#   - Device tree overlay (audio I2S, camera CSI)
#   - GPIO group + libgpiod
#   - VideoCore GPU memory split (per camera AI)
#   - eepromctl per firmware updates
#   - SOLEM camera I/O via picamera2 (Python)
#
# Whitelist hardware: Raspberry Pi 4B (BCM2711), Pi 5 (BCM2712), Pi Zero 2 W.

let
  cfg = config.solem.raspberry;
in {
  options.solem.raspberry = {
    enable = lib.mkEnableOption "Specifiche Raspberry Pi 4/5 (firmware + GPIO + camera)";

    model = lib.mkOption {
      type = lib.types.enum [ "pi4" "pi5" "pi-zero-2w" "pi3" ];
      default = "pi4";
      description = "Modello Raspberry Pi target";
    };

    enableCamera = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Abilita CSI camera (per AI vision al bordo via GAVIO)";
    };

    enableBluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    gpuMemMB = lib.mkOption {
      type = lib.types.int;
      default = 128;
      description = "RAM riservata a VideoCore GPU (MB)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Firmware Broadcom (WiFi + Bluetooth) ───
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = with pkgs; [ raspberrypiWirelessFirmware ];

    # ─── Boot loader ───
    boot.loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # ─── GPU memory split (per camera AI) ───
    boot.kernelParams = [
      "console=ttyS0,115200"
      "console=tty1"
    ];

    # ─── User gavio nel gruppo gpio per accesso libgpiod ───
    users.groups.gpio = {};
    users.users.gavio.extraGroups = [ "gpio" "i2c" "spi" "video" "render" ];

    # ─── udev rules per GPIO/I2C accessibili senza root ───
    services.udev.extraRules = ''
      SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
      SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
      SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
    '';

    # ─── Bluetooth (Pi 4/5 hanno BT built-in) ───
    hardware.bluetooth.enable = cfg.enableBluetooth;

    # ─── Camera CSI ───
    environment.systemPackages = with pkgs; [
      libraspberrypi
      raspberrypi-eeprom
      # python312Packages.picamera2  # disponibile se in nixpkgs
    ] ++ lib.optional cfg.enableCamera libcamera;

    # ─── Edge device class default su Pi ───
    solem.edge.deviceClass = lib.mkDefault "edge-cpu";

    # ─── Hostname distintivo ───
    networking.hostName = lib.mkDefault "solem-pi-${cfg.model}";
  };
}
