{ config, pkgs, lib, ... }:

# SOLEM AIRPLAY RECEIVER — ricevi audio/video da Apple/iOS via AirPlay.
#
# Single responsibility: SOLO orchestrare:
# - Shairport-sync (audio AirPlay 2 receiver, GPL-3.0)
# - uxplay (video mirror AirPlay 2, GPL-3.0)
# - Avahi mDNS per discovery

let
  cfg = config.solem.airplayReceiver;
in {
  options.solem.airplayReceiver = {
    enable = lib.mkEnableOption "AirPlay 2 receiver (audio + video da iPhone/Mac)";

    audio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Shairport-sync per audio (AirPlay 2)";
    };

    video = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "UxPlay per video mirror (richiede GPU per H.264 decode)";
    };

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "SOLEM";
      description = "Nome visibile su iPhone/Mac quando cerca AirPlay";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Avahi obbligatorio per AirPlay discovery
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        publish.enable = true;
      };

      networking.firewall.allowedTCPPorts = [ 5000 7000 7001 7100 ];
      networking.firewall.allowedUDPPorts = [ 5353 6000 6001 7011 ];
    }

    # Shairport-sync (audio)
    (lib.mkIf cfg.audio {
      services.shairport-sync = {
        enable = true;
        arguments = ''-o pipewire -a "${cfg.deviceName}"'';
      };
    })

    # UxPlay (video mirror) — non c'è modulo NixOS, lo installiamo solo
    (lib.mkIf cfg.video {
      environment.systemPackages = with pkgs; [
        uxplay
      ];
      # Helper per lanciare uxplay con nome custom
      environment.etc."solem/airplay-start.sh" = {
        mode = "0755";
        text = ''
          #!${pkgs.bash}/bin/bash
          exec ${pkgs.uxplay}/bin/uxplay -n "${cfg.deviceName}" -nh "$@"
        '';
      };
    })
  ]);
}
