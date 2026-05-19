{ config, pkgs, lib, ... }:

let
  cfg = config.solem.usbguard;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM USBGUARD — controllo USB allowlist
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO USB policy.
  # Allineamento Prompt Master v4.0 sez. 5.1.
  #
  # Default: OFF (può rompere setup laptop con tante USB).
  # Quando attivo: nuovi device USB bloccati finché non approvati esplicitamente.

  options.solem.usbguard = {
    enable = lib.mkEnableOption "USBGuard allowlist (richiede approvazione device USB)";

    presentControllerAllowed = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-allow USB controller già presenti al boot (no lock-out tastiera).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.usbguard = {
      enable = true;
      dbus.enable = true;        # integrazione GUI (es. usbguard-applet-qt)
      # Policy iniziale: solo device già collegati al boot
      presentDevicePolicy = if cfg.presentControllerAllowed then "allow" else "block";
      presentControllerPolicy = "allow";   # NON lockare tastiera/mouse al boot
      insertedDevicePolicy = "apply-policy";
      # Utente gavio può approvare device run-time via D-Bus
      IPCAllowedUsers = [ "gavio" "root" ];
    };

    environment.etc."solem/usbguard-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      present_device_policy = if cfg.presentControllerAllowed then "allow (no lockout)" else "block (strict)";
      inserted_device_policy = "apply-policy (require approval)";
      gui_tools = "usbguard-applet-qt + DBus";
      cli = "usbguard list-devices / allow-device / block-device";
    };
  };
}
