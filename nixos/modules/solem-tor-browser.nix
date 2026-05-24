{ config, pkgs, lib, ... }:

# SOLEM TOR BROWSER — Tor Browser Bundle preinstallato (anonymity browsing).
#
# Single responsibility: SOLO installazione TBB + scorciatoia desktop.
# La config Tor daemon (relay/bridge/onion service) sta in solem-tor.nix.
#
# 100% FOSS, costo 0 €. Privacy by design.

let
  cfg = config.solem.torBrowser;
in {
  options.solem.torBrowser = {
    enable = lib.mkEnableOption "Tor Browser Bundle (anonymity)";

    bridges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Bridge per bypass censura (obfs4 strings)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tor-browser     # in 24.11 il nome è tor-browser (non tor-browser-bundle-bin)
      torsocks        # CLI wrapper per usare Tor con tool generici
    ];

    # Disclaimer al primo lancio
    environment.etc."solem/tor-browser-info.txt".text = ''
      SOLEM — Tor Browser
      ───────────────────
      Tor Browser routa il tuo traffico web attraverso 3 nodi della rete Tor,
      offrendo anonimato di livello superiore. NON usare per:
        - Login a servizi non-Tor (e.g. Gmail)
        - Sites che bloccano Tor (uso non funziona o ti banna)
        - Streaming pesante (lento)

      Usa per:
        - Ricerche sensibili
        - Accesso a .onion services
        - Privacy giornalistica

      Bridges utili (se censurato):
        - Vai su https://bridges.torproject.org per ottenere bridge personalizzati
    '';
  };
}
