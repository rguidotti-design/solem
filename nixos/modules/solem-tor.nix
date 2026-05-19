{ config, pkgs, lib, ... }:

let
  cfg = config.solem.tor;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM TOR — onion routing opt-in
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO Tor client + opzionale onion service.
  # Allineamento Prompt Master v4.0 sez. 3.
  #
  # Default OFF (servizio aggiuntivo, network rallenta).
  # Quando attivo:
  #   - Tor client su 127.0.0.1:9050 (SOCKS) + 9051 (control)
  #   - Opzionale onion service per esporre dashboard SOLEM via .onion
  #     (utile per accesso remoto senza domain pubblico / IP fisso)

  options.solem.tor = {
    enable = lib.mkEnableOption "Tor client SOCKS proxy locale";

    onionService = {
      enable = lib.mkEnableOption "Espone dashboard SOLEM via .onion (per accesso remoto anonimo)";
      mapPort = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Porta onion mappata internamente a localhost:8001 (dashboard).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.tor = {
      enable = true;
      client.enable = true;
      controlSocket.enable = true;
      relay.onionServices = lib.mkIf cfg.onionService.enable {
        "solem-dashboard" = {
          map = [{
            port = cfg.onionService.mapPort;
            target = { addr = "127.0.0.1"; port = 8001; };
          }];
          version = 3;
        };
      };
    };

    environment.systemPackages = with pkgs; [
      tor
      torsocks   # wrapper "torsocks curl ..." per torrificare comandi
    ];

    environment.etc."solem/tor-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      socks_proxy = "127.0.0.1:9050";
      control_socket = "/run/tor/control";
      onion_service_enabled = cfg.onionService.enable;
      onion_hostname_path = lib.mkIf cfg.onionService.enable
        "/var/lib/tor/onion/solem-dashboard/hostname";
      usage = "torsocks <cmd> per usare proxy. cat /var/lib/tor/onion/solem-dashboard/hostname per .onion URL.";
    };
  };
}
