{ config, pkgs, lib, ... }:

# SOLEM WSL — distribuzione SOLEM dentro Windows Subsystem for Linux 2.
#
# Single responsibility: SOLO config WSL-specific:
#   - kernel WSL (no boot loader)
#   - systemd via WSL2 (Win11+, opzionale)
#   - mount /mnt/c con metadata=case=off
#   - bridge clipboard/network con Windows host
#   - utente di default "gavio" (no autologin)
#
# Build:
#   nix build .#wsl
#   wsl --import SOLEM C:\WSL\SOLEM .\result\tarball\nixos-wsl-*.tar.gz
#   wsl -d SOLEM

let
  cfg = config.solem.wsl;
in {
  options.solem.wsl = {
    enable = lib.mkEnableOption "WSL2 SOLEM distribution";

    defaultUser = lib.mkOption {
      type = lib.types.str;
      default = "gavio";
    };

    interopAppendWindowsPath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Aggiungi PATH Windows a $PATH (rallenta shell)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── WSL-specific (no bootloader, no init) ──
    boot.isContainer = false;
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;

    # ── systemd in WSL ──
    systemd.services."serial-getty@ttyS0".enable = false;
    systemd.services."serial-getty@hvc0".enable = false;
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@".enable = false;

    # ── User di default ──
    users.users.${cfg.defaultUser} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "users" ];
      shell = pkgs.bash;
    };

    # WSL conf
    environment.etc."wsl.conf".text = ''
      [boot]
      systemd=true
      command="${pkgs.bash}/bin/bash -c 'echo SOLEM WSL ready'"

      [user]
      default=${cfg.defaultUser}

      [interop]
      enabled=true
      appendWindowsPath=${if cfg.interopAppendWindowsPath then "true" else "false"}

      [network]
      hostname=solem-wsl
      generateHosts=true
      generateResolvConf=true

      [automount]
      enabled=true
      root=/mnt/
      options=metadata,umask=22,fmask=11,case=off
    '';

    # ── Niente desktop, niente NetworkManager (Windows lo gestisce) ──
    networking.networkmanager.enable = lib.mkForce false;
    services.xserver.enable = lib.mkForce false;

    # ── Tool dev essenziali ──
    environment.systemPackages = with pkgs; [
      git curl wget vim
      python312 nodejs_22 go rustc cargo
      docker-client  # client per Docker Desktop Windows
    ];

    # ── Hostname ──
    networking.hostName = lib.mkDefault "solem-wsl";

    # ── Edge class ──
    solem.edge.deviceClass = lib.mkDefault "workstation";

    # ── State version ──
    system.stateVersion = "24.11";
  };
}
