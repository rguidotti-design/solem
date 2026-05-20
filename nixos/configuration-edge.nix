{ config, pkgs, lib, ... }:

# SOLEM EDGE — configurazione base per device ARM64 low-power.
#
# Differenza vs configuration.nix (workstation):
#   - NO desktop (Hyprland/Cage)
#   - NO Ollama 70b (RAM 2-8 GB)
#   - NO Plymouth animato (CPU limitata)
#   - ZRAM al posto di swap su disco
#   - Journal volatile (preserva SD card)
#   - WiFi + ssh by default (deploy headless)
#   - SOLEM API in modalità worker (registra al gateway)

{
  imports = [
    # Layer SOLEM minimi necessari anche su edge
    ./modules/solem-api.nix
    ./modules/solem-server-mode.nix
    ./modules/solem-cluster.nix
  ];

  # Boot leggero: niente plymouth, console-only
  boot.loader.timeout = lib.mkDefault 1;
  boot.consoleLogLevel = lib.mkDefault 3;

  # ─── User edge ───
  users.users.gavio = {
    isNormalUser = true;
    description = "SOLEM edge worker";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "gpio" "i2c" "dialout" ];
    initialPassword = lib.mkDefault "gavio";  # da cambiare al primo login
    openssh.authorizedKeys.keys = [
      # Aggiungi qui le pubkey SSH per accesso headless
    ];
  };

  # ─── Network: headless ready (WiFi + SSH + mesh) ───
  networking = {
    networkmanager.enable = true;
    wireless.enable = false;  # NetworkManager gestisce WiFi
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 8001 ];  # SSH + SOLEM API
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # solo per first-boot setup
      PermitRootLogin = "no";
    };
  };

  # ─── Server mode + cluster worker ───
  solem.serverMode.enable = true;
  solem.serverMode.enableMdns = true;
  solem.cluster.enable = true;
  solem.cluster.role = "worker";  # questo nodo è worker, non gateway

  # ─── Localizzazione ───
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "it";

  # ─── Stato system ───
  system.stateVersion = "24.11";

  # ─── Tool essenziali edge ───
  environment.systemPackages = with pkgs; [
    git curl vim htop tmux jq
    iputils iproute2
    usbutils pciutils
    libgpiod      # GPIO control da CLI
    i2c-tools     # I2C debug
  ];
}
