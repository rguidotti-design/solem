{ config, pkgs, lib, ... }:

# SOLEM SERVER MODE — il PC è (anche) un server: headless, sempre acceso,
# accessibile da rete, ottimizzato per servire GAVIO h24.
#
# Single responsibility: SOLO config "macchina server" — niente desktop,
# niente sleep, niente power-down disk, SSH abilitato, watchdog hardware,
# log centralizzato locale.
#
# Quando attivato: il box diventa un server casalingo perfetto per ospitare
# GAVIO + tutti i self-host moduli + mesh ingress, accessibile da
# smartphone/tablet/PC nella rete (e via mesh esterna).

let
  cfg = config.solem.serverMode;
in {
  options.solem.serverMode = {
    enable = lib.mkEnableOption "Server mode (headless, always-on, network-exposed)";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "solem";
      description = "Hostname server (visibile in mDNS come solem.local)";
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 22;
    };

    sshAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Chiavi SSH autorizzate per gavio user (passwd auth è disabilitato)";
    };

    enableMdns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pubblica solem.local via avahi mDNS";
    };

    enableWatchdog = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hardware watchdog systemd (reboot in caso di hang)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hostName = cfg.hostname;

    # ── SSH server ──
    services.openssh = {
      enable = true;
      ports = [ cfg.sshPort ];
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        X11Forwarding = false;
        AllowUsers = [ "gavio" ];
        MaxAuthTries = 3;
        ClientAliveInterval = 30;
        ClientAliveCountMax = 3;
      };
    };

    users.users.gavio.openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;

    # ── No sleep / no suspend (server sempre acceso) ──
    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };

    services.logind = {
      lidSwitch = "ignore";
      lidSwitchDocked = "ignore";
      lidSwitchExternalPower = "ignore";
      extraConfig = ''
        HandlePowerKey=ignore
        HandleSuspendKey=ignore
        HandleHibernateKey=ignore
        IdleAction=ignore
      '';
    };

    powerManagement.enable = false;

    # ── No disk spindown (latency-sensitive per Ollama) ──
    services.fstrim.enable = true;  # SSD trim weekly

    # ── Watchdog hardware ──
    systemd.watchdog = lib.mkIf cfg.enableWatchdog {
      runtimeTime = "30s";
      rebootTime = "10min";
    };

    # ── mDNS solem.local ──
    services.avahi = lib.mkIf cfg.enableMdns {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
    };

    # ── Boot ordinato: GAVIO + SOLEM API + Ollama al boot ──
    systemd.targets.multi-user.wants = [
      "solem-api.service"
      "gavio.service"
      "ollama.service"
    ];

    # ── Log persistenti su disco (anche dopo reboot) ──
    services.journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=2G
      MaxRetentionSec=30day
    '';

    # ── Banner SSH ──
    services.openssh.banner = ''

      ┌────────────────────────────────────────────────┐
      │  SOLEM — AI-native OS · server mode           │
      │  Host: ${cfg.hostname} · GAVIO + selfhost     │
      │  Accesso solo via SSH key. No password.        │
      └────────────────────────────────────────────────┘
    '';

    # ── Tool sysadmin sempre disponibili ──
    environment.systemPackages = with pkgs; [
      htop btop iotop nethogs iftop bandwhich
      tmux zellij screen
      lsof ncdu dust duf
      smartmontools nvme-cli
      tcpdump iperf3 mtr
    ];
  };
}
