{ config, pkgs, lib, ... }:

# SOLEM INIT — installa il wizard onboarding come comando di sistema.
#
# Single responsibility: SOLO impacchettare lo script come binario in $PATH
# e creare la directory /etc/solem. Nessuna logica di config (è nello
# script bash).

let
  initScript = pkgs.writeShellApplication {
    name = "solem-init";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../../scripts/solem-init.sh;
  };
in {
  environment.systemPackages = [ initScript ];

  # Directory /etc/solem deve esistere per onboarding.json
  systemd.tmpfiles.rules = [
    "d /etc/solem 0755 root root - -"
  ];

  # MOTD post-login se onboarding non fatto
  environment.etc."issue.solem".text = ''

       ╔═══════════════════════════════════════════════╗
       ║    SOLEM — AI-native OS                       ║
       ║    Primo boot? Esegui:  sudo solem-init       ║
       ╚═══════════════════════════════════════════════╝

  '';
}
