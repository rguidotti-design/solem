{ config, pkgs, lib, ... }:

# SOLEM SUSPEND FIX — hooks pre/post suspend per bug ricorrenti Linux.
#
# Single responsibility: SOLO unit systemd-suspend@.service hook che:
# - pre-suspend: kill Bluetooth, unload moduli problematici (rtw_8821ce ecc.)
# - post-resume: ricarica moduli, riavvia NetworkManager, reset audio PipeWire

let
  cfg = config.solem.suspendFix;
in {
  options.solem.suspendFix = {
    enable = lib.mkEnableOption "Fix bug ricorrenti Linux suspend/resume";

    problematicModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Lista moduli kernel da scaricare prima del suspend.
        Esempi noti che rompono il resume:
          - rtw_8821ce (Realtek Wi-Fi su alcuni laptop ASUS)
          - rtw_8822ce
          - btusb (alcuni Bluetooth Intel)
      '';
    };

    restartNetworkOnResume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Riavvia NetworkManager dopo resume (fix Wi-Fi che non riconnette)";
    };

    resetAudioOnResume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Riavvia PipeWire dopo resume (fix audio che resta muto)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hook pre-suspend: unload moduli problematici
    powerManagement.powerDownCommands = lib.optionalString
      (cfg.problematicModules != [])
      (lib.concatMapStringsSep "\n" (mod: ''
        ${pkgs.kmod}/bin/modprobe -r ${mod} || true
      '') cfg.problematicModules);

    # Hook post-resume: reload moduli + reset network/audio
    powerManagement.resumeCommands = lib.concatStringsSep "\n" (
      (lib.optionals (cfg.problematicModules != []) (
        map (mod: "${pkgs.kmod}/bin/modprobe ${mod} || true")
            cfg.problematicModules
      ))
      ++ lib.optional cfg.restartNetworkOnResume
        "${pkgs.systemd}/bin/systemctl restart NetworkManager.service || true"
      ++ lib.optional cfg.resetAudioOnResume ''
        ${pkgs.systemd}/bin/systemctl --user -M $UID@.host restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
      ''
    );

    # Log diagnostico (uname + suspend count)
    environment.etc."solem/suspend-fix.md".text = ''
      # Suspend fix attivo
      Moduli scaricati al suspend: ${lib.concatStringsSep ", " cfg.problematicModules}
      Reset NetworkManager al resume: ${if cfg.restartNetworkOnResume then "sì" else "no"}
      Reset PipeWire al resume: ${if cfg.resetAudioOnResume then "sì" else "no"}

      ## Se hai ancora problemi resume

      Identifica il modulo colpevole:
      ```
      sudo dmesg | grep -i "resume\|suspend" | tail -20
      ```

      Aggiungilo in configuration.nix:
      ```nix
      solem.suspendFix.problematicModules = [ "rtw_8821ce" "btusb" ];
      ```
    '';
  };
}
