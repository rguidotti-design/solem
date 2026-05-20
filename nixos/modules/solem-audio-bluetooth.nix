{ config, pkgs, lib, ... }:

# SOLEM AUDIO+BLUETOOTH — PipeWire + BlueZ opt-in.
#
# Single responsibility: SOLO abilitare stack audio moderno PipeWire +
# bluetooth audio. Niente UI (è in solem-desktop), niente codec proprietari
# (LDAC va abilitato esplicitamente).
#
# 100% FOSS, costo 0 €.

let
  cfg = config.solem.audioBluetooth;
in {
  options.solem.audioBluetooth = {
    enable = lib.mkEnableOption "Audio moderno (PipeWire) + Bluetooth";

    pipewire = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "PipeWire come server audio (sostituisce PulseAudio)";
    };

    bluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "BlueZ bluetooth stack";
    };

    aptxLdac = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Codec aptX/LDAC (richiede pacchetti non-free in alcuni casi)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # PipeWire
    (lib.mkIf cfg.pipewire {
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
        wireplumber.enable = true;
      };

      environment.systemPackages = with pkgs; [
        pavucontrol
        playerctl
        helvum  # patchbay PipeWire
      ];
    })

    # Bluetooth
    (lib.mkIf cfg.bluetooth {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General = {
            Enable = "Source,Sink,Media,Socket";
            Experimental = true;  # serve per battery reporting su alcuni device
            FastConnectable = true;
            JustWorksRepairing = "always";
          };
        };
      };

      services.blueman.enable = true;

      environment.systemPackages = with pkgs; [
        bluez
        bluez-tools
      ];
    })

    # Codec extra (aptX/LDAC via libfreeaptx + ldacBT)
    (lib.mkIf (cfg.bluetooth && cfg.aptxLdac) {
      environment.systemPackages = with pkgs; [
        libfreeaptx
        ldacbt
      ];
    })
  ]);
}
