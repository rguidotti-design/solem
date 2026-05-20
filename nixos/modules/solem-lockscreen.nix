{ config, pkgs, lib, ... }:

# SOLEM LOCKSCREEN — swaylock + swayidle config branded.
#
# Single responsibility: SOLO config lock screen + idle timer. Niente UI
# (è in desktop module).
#
# Brand: navy background + Cormorant. 100% FOSS, 0 €.

let
  cfg = config.solem.lockscreen;
in {
  options.solem.lockscreen = {
    enable = lib.mkEnableOption "Lock screen automatico (swaylock + swayidle)";

    idleSeconds = lib.mkOption {
      type = lib.types.int;
      default = 600;  # 10 min
      description = "Inattività prima del lock";
    };

    dpmsSeconds = lib.mkOption {
      type = lib.types.int;
      default = 900;  # 15 min
      description = "Inattività prima dello spegnimento schermo";
    };

    suspendSeconds = lib.mkOption {
      type = lib.types.int;
      default = 1800;  # 30 min
      description = "Inattività prima del suspend (0 = mai)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      swaylock-effects
      swayidle
    ];

    # PAM per swaylock (richiesto su NixOS per auth)
    security.pam.services.swaylock = {};

    # Config swaylock branded
    environment.etc."xdg/swaylock/config".text = ''
      daemonize
      ignore-empty-password
      indicator-radius=80
      indicator-thickness=8
      color=0a1628
      ring-color=c9a961
      key-hl-color=c9a961
      bs-hl-color=d97757
      ring-clear-color=8aa67b
      ring-ver-color=6b8aa3
      ring-wrong-color=d97757
      inside-color=0a1628aa
      inside-clear-color=8aa67baa
      inside-ver-color=6b8aa3aa
      inside-wrong-color=d97757aa
      line-color=00000000
      separator-color=00000000
      text-color=e8eaed
      text-clear-color=e8eaed
      text-ver-color=e8eaed
      text-wrong-color=e8eaed
      font=Cormorant Garamond
      font-size=24
      effect-blur=8x4
      effect-vignette=0.5:0.5
    '';

    # swayidle user service
    systemd.user.services.swayidle = {
      description = "SOLEM — idle daemon (auto-lock)";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.swayidle}/bin/swayidle -w \
            timeout ${toString cfg.idleSeconds} '${pkgs.swaylock-effects}/bin/swaylock' \
            timeout ${toString cfg.dpmsSeconds} '${pkgs.wlr-randr}/bin/wlr-randr --output \"*\" --off' \
              resume '${pkgs.wlr-randr}/bin/wlr-randr --output \"*\" --on' \
            ${lib.optionalString (cfg.suspendSeconds > 0) ''
              timeout ${toString cfg.suspendSeconds} 'systemctl suspend' \
            ''}
            before-sleep '${pkgs.swaylock-effects}/bin/swaylock'
        '';
        Restart = "on-failure";
      };
    };
  };
}
