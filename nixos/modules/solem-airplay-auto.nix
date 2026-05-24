{ config, pkgs, lib, ... }:

# SOLEM AIRPLAY AUTO — ricevi audio/video da iPhone/Mac automaticamente.
#
# Single responsibility: SOLO orchestrare shairport-sync (audio, FOSS GPL-3)
# + uxplay (video mirror, FOSS GPL-3) come servizi systemd autostart.
#
# Quando attivo: SOLEM appare in iPhone/Mac come destinazione AirPlay.
# Niente account Apple richiesto sul lato SOLEM.

let
  cfg = config.solem.airplayAuto;
in {
  options.solem.airplayAuto = {
    enable = lib.mkEnableOption "AirPlay 2 receiver auto (audio + video da Apple)";

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "SOLEM";
      description = "Nome visibile su iPhone/Mac";
    };

    audio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Shairport-sync audio receiver";
    };

    video = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        UxPlay video mirror (richiede GPU H.264 decode + display attivo).
        Off di default — abilitare solo se vuoi mirror schermo iPhone su SOLEM.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Avahi obbligatorio per AirPlay discovery (mDNS)
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        publish.enable = true;
      };

      # Apri porte AirPlay (solo LAN; non esponete a internet)
      networking.firewall = {
        allowedTCPPorts = [ 5000 7000 7001 7100 ];
        allowedUDPPorts = [ 5353 6000 6001 7011 ];
      };
    }

    (lib.mkIf cfg.audio {
      services.shairport-sync = {
        enable = true;
        arguments = ''-o pipewire -a "${cfg.deviceName}"'';
      };
    })

    (lib.mkIf cfg.video {
      environment.systemPackages = with pkgs; [ uxplay ];
      systemd.services.uxplay = {
        description = "SOLEM UxPlay AirPlay video receiver";
        wantedBy = [ "graphical.target" ];
        after = [ "graphical.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.uxplay}/bin/uxplay -n ${cfg.deviceName} -nh";
          Restart = "on-failure";
        };
      };
    })

    # Helper info
    {
      environment.etc."solem/airplay-info.txt".text = ''
        SOLEM AirPlay Auto

        Nome visibile: ${cfg.deviceName}
        Audio: ${if cfg.audio then "sì (shairport-sync)" else "no"}
        Video: ${if cfg.video then "sì (uxplay)" else "no"}

        Da iPhone:
          Centro di Controllo → AirPlay → cerca '${cfg.deviceName}' (audio)
          App: tap icona AirPlay → '${cfg.deviceName}'

        Da Mac:
          System Settings → Screen Mirroring → '${cfg.deviceName}'

        Niente account Apple richiesto sul SOLEM.
      '';
    }
  ]);
}
