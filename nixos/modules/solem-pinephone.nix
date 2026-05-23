{ config, pkgs, lib, ... }:

# SOLEM PINEPHONE — profilo per PinePhone / PinePhone Pro (aarch64 Linux phone).
#
# Single responsibility: SOLO config Pi64/Pro-specific:
#   - Bootloader U-Boot + device tree Allwinner A64 / Rockchip RK3399S
#   - Modem libsalt + mobile broadband (ofono)
#   - Phosh/Plasma Mobile (touch-friendly)
#   - Power saving aggressivo (batteria limited)
#
# 100% FOSS. Sostituisce postmarketOS/Mobian con SOLEM stack.

let
  cfg = config.solem.pinephone;
in {
  options.solem.pinephone = {
    enable = lib.mkEnableOption "PinePhone / PinePhone Pro support";

    model = lib.mkOption {
      type = lib.types.enum [ "pinephone" "pinephone-pro" ];
      default = "pinephone";
    };

    shell = lib.mkOption {
      type = lib.types.enum [ "phosh" "plasma-mobile" "sxmo" ];
      default = "phosh";
      description = "Mobile shell: phosh (GNOME), plasma-mobile (KDE), sxmo (suckless minimal)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Hardware ──
    hardware.enableRedistributableFirmware = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # ── Mobile broadband (modem) ──
    networking.modemmanager.enable = true;
    services.ofono.enable = true;

    # ── Mobile shell ──
    services.xserver.desktopManager.phosh = lib.mkIf (cfg.shell == "phosh") {
      enable = true;
      user = "gavio";
    };

    services.xserver.displayManager = lib.mkIf (cfg.shell == "plasma-mobile") {
      sddm.enable = true;
    };
    services.desktopManager.plasma6 = lib.mkIf (cfg.shell == "plasma-mobile") {
      enable = true;
      enableQt5Integration = true;
    };

    environment.systemPackages = with pkgs; [
      mobile-broadband-provider-info
      callaudiod   # audio routing per chiamate
    ] ++ lib.optionals (cfg.shell == "phosh") (with pkgs; [
      gnome-calls gnome-contacts gnome-clocks
      gnome-text-editor chatty
    ]) ++ lib.optionals (cfg.shell == "sxmo") (with pkgs; [
      sxmo-utils
    ]);

    # ── Edge profile auto-set ──
    solem.edge.enable = lib.mkDefault true;
    solem.edge.deviceClass = lib.mkDefault "mobile";

    # ── Hostname ──
    networking.hostName = lib.mkDefault "solem-pinephone";

    # ── Power saving aggressivo ──
    powerManagement.cpuFreqGovernor = lib.mkForce "ondemand";
    services.tlp.enable = true;
  };
}
