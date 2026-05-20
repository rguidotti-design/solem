{ config, pkgs, lib, ... }:

{
  # Networking di base — VM e bare-metal.
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22      # SSH
      8000    # GAVIO API (HTTP)
      8001    # SOLEM Identity service (placeholder L1)
      8002    # SOLEM Context service (placeholder L2)
      11434   # Ollama (locale)
    ];
    # ICMP echo OK per ping
    allowPing = true;
  };

  # SSH: indispensabile per accedere alla VM headless via `ssh -p 2222 gavio@localhost`
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault true;   # OK in VM; disattiva in produzione
      KbdInteractiveAuthentication = lib.mkDefault false;
      X11Forwarding = lib.mkDefault false;
    };
  };

  # WireGuard placeholder (Step 1+): collega device esterni al server SOLEM.
  # networking.wireguard.interfaces.wg0 = {
  #   ips = [ "10.100.0.1/24" ];
  #   listenPort = 51820;
  #   privateKeyFile = "/var/lib/wireguard/server.key";
  #   peers = [ /* device utente */ ];
  # };

  # mDNS / Avahi: scoperta servizi locali (utile per multi-device futuro)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
