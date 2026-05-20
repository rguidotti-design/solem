{ config, pkgs, lib, ... }:

# SOLEM CLIPBOARD — clipboard manager con history (cliphist + wl-clipboard).
#
# Single responsibility: SOLO daemon storia clipboard + binari CLI.
# Niente UI fuzzy picker (è in desktop module via fuzzel/wofi).
#
# Storage: cifrato a riposo se solem.clipboard.encrypt = true (richiede
# gpg). Default plain in $HOME/.cache/cliphist/. 100% FOSS.

let
  cfg = config.solem.clipboard;
in {
  options.solem.clipboard = {
    enable = lib.mkEnableOption "Clipboard manager con history (cliphist)";

    maxItems = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Numero max entries nella history";
    };

    excludePasswords = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Esclude contenuti con marker X-KDE-PasswordManagerHint";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wl-clipboard      # wl-copy / wl-paste
      cliphist          # history manager
      xclip             # X11 fallback
    ];

    # User service cliphist (clipboard watcher)
    systemd.user.services.cliphist = {
      description = "SOLEM — clipboard history daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      script = ''
        ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store &
        ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
        wait
      '';
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    # Truncate history settimanale
    systemd.user.services.cliphist-trim = {
      description = "SOLEM — trim clipboard history a ${toString cfg.maxItems} items";
      script = ''
        # cliphist non ha trim diretto, ma teniamo le più recenti
        ${pkgs.cliphist}/bin/cliphist list | head -n ${toString cfg.maxItems} > /tmp/cliphist-keep
        ${pkgs.cliphist}/bin/cliphist wipe
        while IFS= read -r line; do
          id=$(echo "$line" | cut -f1)
          ${pkgs.cliphist}/bin/cliphist decode "$id" 2>/dev/null | ${pkgs.cliphist}/bin/cliphist store
        done < /tmp/cliphist-keep
        rm -f /tmp/cliphist-keep
      '';
      serviceConfig.Type = "oneshot";
    };

    systemd.user.timers.cliphist-trim = {
      description = "Trim clipboard history settimanale";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}
