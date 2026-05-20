{ config, pkgs, lib, ... }:

# SOLEM PASSWORD MANAGER — KeePassXC integrato + agent SSH/GPG.
#
# Single responsibility: SOLO installazione client + agent unlock.
# Storage del DB sta in ~/.local/share/keepass/, sync via Syncthing.
#
# Vantaggi vs LastPass/1Password/Dashlane:
#   - 100% offline, niente cloud
#   - FOSS (KeePassXC), costo 0 € (vs 35-60€/anno LastPass)
#   - SSH agent integrato (no ssh-agent separato)
#
# 100% FOSS, 0 €.

let
  cfg = config.solem.passwordManager;
in {
  options.solem.passwordManager = {
    enable = lib.mkEnableOption "KeePassXC password manager + agent";

    sshAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Usa KeePassXC come agent SSH (sostituisce ssh-agent)";
    };

    browserIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Native messaging host per estensione browser";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avvio automatico al login (minimizzato in tray)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      keepassxc
      passff-host       # Firefox native messaging
    ];

    # Native messaging host per estensione browser (Firefox + Chromium)
    environment.etc = lib.mkIf cfg.browserIntegration {
      "mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".source =
        "${pkgs.keepassxc}/etc/mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json";
      "chromium/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".source =
        "${pkgs.keepassxc}/etc/chromium/native-messaging-hosts/org.keepassxc.keepassxc_browser.json";
    };

    # Service user autostart
    systemd.user.services.keepassxc = lib.mkIf cfg.autoStart {
      description = "KeePassXC password manager";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.keepassxc}/bin/keepassxc";
        Restart = "on-failure";
      };
    };

    # SSH config per agent KeePassXC
    programs.ssh = lib.mkIf cfg.sshAgent {
      startAgent = false;  # disabilita ssh-agent ufficiale
      extraConfig = ''
        # SOLEM: KeePassXC SSH agent
        IdentityAgent ~/.ssh/keepassxc-ssh-agent.sock
      '';
    };
  };
}
