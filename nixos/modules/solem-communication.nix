{ config, pkgs, lib, ... }:

# SOLEM COMMUNICATION — voice/video/chat self-host (alternativa Discord/Zoom).
#
# Single responsibility: SOLO orchestrare Jitsi Meet + Mumble + Synapse
# (Matrix) + Mastodon. Tutti opt-in indipendenti.

let
  cfg = config.solem.communication;
in {
  options.solem.communication = {
    mumble = {
      enable = lib.mkEnableOption "Mumble VoIP server (gaming voice chat low-latency)";
      port = lib.mkOption { type = lib.types.port; default = 64738; };
    };

    jitsi = {
      enable = lib.mkEnableOption "Jitsi Meet (video conferencing Zoom alternative)";
      hostname = lib.mkOption {
        type = lib.types.str;
        default = "meet.solem.local";
      };
    };

    matrix = {
      enable = lib.mkEnableOption "Matrix Synapse homeserver (E2E federato)";
      serverName = lib.mkOption {
        type = lib.types.str;
        default = "solem.local";
      };
    };

    mastodon = {
      enable = lib.mkEnableOption "Mastodon (microblogging federato, alternative Twitter)";
      localDomain = lib.mkOption {
        type = lib.types.str;
        default = "social.solem.local";
      };
    };
  };

  config = lib.mkMerge [
    # Mumble
    (lib.mkIf cfg.mumble.enable {
      services.murmur = {
        enable = true;
        port = cfg.mumble.port;
        bandwidth = 130000;            # 130kbps high-quality
        welcometext = "Benvenuto sul server Mumble di SOLEM";
      };
      networking.firewall.allowedTCPPorts = [ cfg.mumble.port ];
      networking.firewall.allowedUDPPorts = [ cfg.mumble.port ];
    })

    # Jitsi Meet
    (lib.mkIf cfg.jitsi.enable {
      services.jitsi-meet = {
        enable = true;
        hostName = cfg.jitsi.hostname;
        nginx.enable = true;
        # JWT auth opt
        # interfaceConfig.SHOW_JITSI_WATERMARK = false;
        config = {
          enableWelcomePage = false;
          prejoinPageEnabled = true;
        };
      };
    })

    # Matrix Synapse
    (lib.mkIf cfg.matrix.enable {
      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = cfg.matrix.serverName;
          public_baseurl = "https://${cfg.matrix.serverName}";
          enable_registration = false;     # solo invite
          registration_requires_token = true;
          listeners = [{
            port = 8008;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [{ names = [ "client" "federation" ]; compress = false; }];
          }];
        };
      };
    })

    # Mastodon
    (lib.mkIf cfg.mastodon.enable {
      services.mastodon = {
        enable = true;
        localDomain = cfg.mastodon.localDomain;
        smtp = {
          authenticate = false;
          host = "127.0.0.1";
          fromAddress = "mastodon@${cfg.mastodon.localDomain}";
        };
        configureNginx = true;
      };
    })
  ];
}
