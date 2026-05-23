{ config, pkgs, lib, ... }:

# SOLEM CHAT CLIENTS — client desktop FOSS per chat federate / E2EE.
#
# Single responsibility: SOLO installare CLIENT desktop FOSS. I server
# (Matrix Synapse, Jitsi, Mumble) sono in solem-communication.nix.
#
# Client inclusi (tutti FOSS, E2EE by default):
# - Element       → Matrix (Apache-2.0)
# - SimpleX       → no-identity messenger (AGPL-3.0)
# - Jami          → P2P video/voce (GPL-3.0, ex GNU Ring)
# - Delta Chat    → chat su top di SMTP/IMAP (GPL-3.0)
# - Dino          → XMPP moderno (GPL-3.0)
# - Gajim         → XMPP completo (GPL-3.0)
# - Cinny         → Matrix client UI moderna (AGPL-3.0)
# - FluffyChat    → Matrix mobile-first (AGPL-3.0)
# - Briar         → mesh + Tor (GPL-3.0, future-work)
#
# 0 €. Niente WhatsApp / Telegram-desktop di default (closed/dipendenze cloud).

let
  cfg = config.solem.chatClients;
in {
  options.solem.chatClients = {
    enable = lib.mkEnableOption "Client chat FOSS (Element/SimpleX/Jami/Delta/Dino)";

    matrix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Element + Cinny + FluffyChat (Matrix federation)";
    };

    simplex = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "SimpleX Chat (no-identity, no metadata)";
    };

    jami = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Jami (ex GNU Ring) — video/voce P2P senza server centrale";
    };

    deltaChat = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Delta Chat — chat E2EE su SMTP/IMAP standard";
    };

    xmpp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Dino + Gajim (client XMPP/Jabber)";
    };

    signal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Signal Desktop. Signal-app è AGPL-3.0 ma dipende da server centralizzato
        operato da Signal Foundation (no self-host). Off di default per
        coerenza con preferenza federazione/P2P. Abilita esplicitamente.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [

      (lib.optionals cfg.matrix [
        element-desktop      # Matrix client classico
        cinny-desktop        # Matrix UI moderna
        # fluffychat        # mobile-first, controllo disponibilità
      ])

      (lib.optionals cfg.simplex [
        simplex-chat-desktop
      ])

      (lib.optionals cfg.jami [
        jami
      ])

      (lib.optionals cfg.deltaChat [
        deltachat-desktop
      ])

      (lib.optionals cfg.xmpp [
        dino
        gajim
      ])

      (lib.optionals cfg.signal [
        signal-desktop
      ])
    ];
  };
}
