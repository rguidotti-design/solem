{ config, pkgs, lib, ... }:

# SOLEM POWER — gestione energia (TLP, thermald, suspend, hibernate).
#
# Single responsibility: SOLO config power management. Niente UI, niente
# notifiche batteria (è in desktop).
#
# Profili:
#   - laptop  → TLP aggressivo, GPU runtime PM, battery thresholds
#   - desktop → minimo intervento, performance default
#   - server  → niente sleep, niente idle
#
# Tutto FOSS, costo 0 €.

let
  cfg = config.solem.power;
in {
  options.solem.power = {
    enable = lib.mkEnableOption "Power management (TLP + thermald)";

    profile = lib.mkOption {
      type = lib.types.enum [ "laptop" "desktop" "server" ];
      default = "laptop";
      description = "Profilo power management";
    };

    batteryStartCharge = lib.mkOption {
      type = lib.types.int;
      default = 75;
      description = "Inizia carica solo sotto questa soglia (longevità)";
    };

    batteryStopCharge = lib.mkOption {
      type = lib.types.int;
      default = 85;
      description = "Smetti carica a questa soglia (longevità)";
    };

    suspendOnLidClose = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [

    # Common: thermald + powertop
    {
      services.thermald.enable = true;
      environment.systemPackages = with pkgs; [ powertop acpi ];
    }

    # ── LAPTOP profile ──
    (lib.mkIf (cfg.profile == "laptop") {
      services.tlp = {
        enable = true;
        settings = {
          CPU_SCALING_GOVERNOR_ON_AC  = "performance";
          CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
          CPU_ENERGY_PERF_POLICY_ON_AC  = "performance";
          CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

          # Battery longevity (Lenovo/Thinkpad ASUS etc.)
          START_CHARGE_THRESH_BAT0 = cfg.batteryStartCharge;
          STOP_CHARGE_THRESH_BAT0  = cfg.batteryStopCharge;
          START_CHARGE_THRESH_BAT1 = cfg.batteryStartCharge;
          STOP_CHARGE_THRESH_BAT1  = cfg.batteryStopCharge;

          # Disk power
          DISK_IDLE_SECS_ON_BAT = 2;
          MAX_LOST_WORK_SECS_ON_BAT = 60;

          # Runtime PM USB
          USB_AUTOSUSPEND = 1;
          USB_EXCLUDE_AUDIO = 1;  # niente suspend per audio devices
          USB_EXCLUDE_BTUSB = 1;
        };
      };

      services.logind = lib.mkIf cfg.suspendOnLidClose {
        lidSwitch = "suspend";
        lidSwitchExternalPower = "ignore";
      };

      powerManagement.powertop.enable = true;
    })

    # ── DESKTOP profile ──
    (lib.mkIf (cfg.profile == "desktop") {
      powerManagement.cpuFreqGovernor = "schedutil";
      services.logind.lidSwitch = "ignore";
    })

    # ── SERVER profile ──
    (lib.mkIf (cfg.profile == "server") {
      powerManagement.cpuFreqGovernor = "performance";
      powerManagement.enable = false;
      services.logind = {
        lidSwitch = "ignore";
        lidSwitchExternalPower = "ignore";
        extraConfig = ''
          HandlePowerKey=ignore
          IdleAction=ignore
        '';
      };
    })
  ]);
}
