{ config, pkgs, lib, ... }:

# SOLEM CHANNELS — canale update stable/testing/nightly.
#
# Single responsibility: SOLO selezione del canale flake da cui tirare
# update. La logica check/apply/rollback è in solem_api/layers/updates.py.
#
# Canali:
#   - stable    → main branch (raccomandato)
#   - testing   → testing branch (RC pre-stable, instabile ma sicuro)
#   - nightly   → main HEAD aggiornato continuamente (può rompere)

let
  cfg = config.solem.channel;

  channelUrls = {
    stable  = "github:rguidotti-design/solem/main";
    testing = "github:rguidotti-design/solem/testing";
    nightly = "github:rguidotti-design/solem/nightly";
  };

  updateScript = pkgs.writeShellApplication {
    name = "solem-channel-set";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      CHANNEL="''${1:-stable}"
      case "$CHANNEL" in
        stable|testing|nightly)
          echo "$CHANNEL" | sudo tee /etc/solem/channel >/dev/null
          echo "Channel set to: $CHANNEL"
          echo "Per applicare: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;
        *)
          echo "Channel sconosciuto: $CHANNEL"
          echo "Disponibili: stable | testing | nightly"
          exit 1
          ;;
      esac
    '';
  };
in {
  options.solem.channel = {
    enable = lib.mkEnableOption "Channel switcher stable/testing/nightly";

    current = lib.mkOption {
      type = lib.types.enum [ "stable" "testing" "nightly" ];
      default = "stable";
      description = "Canale corrente. Cambia via `solem-channel-set <name>`.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ updateScript ];

    # File che la API legge per sapere quale canale siamo
    environment.etc."solem/channel".text = cfg.current;
    environment.etc."solem/channel-urls.json".text = builtins.toJSON channelUrls;

    # Banner che spiega
    environment.etc."solem/channels.md".text = ''
      # SOLEM update channels

      ## stable
      Branch `main`. Releases tagged. Update settimanali/mensili.
      Tutti i fix critici sono back-portati qui. **Default raccomandato.**

      ## testing
      Branch `testing`. Release candidate prima di promuovere a stable.
      Aggiornato ~settimanale. Bug minori possibili.

      ## nightly
      Branch `main` HEAD. Aggiornato continuamente.
      Può rompersi. Solo per dev che vogliono provare il prossimo.

      ## Switch
      ```bash
      solem-channel-set testing
      sudo nixos-rebuild switch --flake /etc/nixos
      ```

      Rollback automatico: scegli la generation precedente da GRUB.
    '';
  };
}
