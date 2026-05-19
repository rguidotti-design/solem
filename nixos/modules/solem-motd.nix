{ config, pkgs, lib, ... }:

let
  # Banner ASCII art SOLEM — mostrato a /etc/issue (pre-login) e MOTD (post-login).
  # Stile minimal, in linea con palette bordeaux/oro (qui solo ASCII).
  banner = ''


       ███████╗  ██████╗  ██╗      ███████╗ ███╗   ███╗
       ██╔════╝ ██╔═══██╗ ██║      ██╔════╝ ████╗ ████║
       ███████╗ ██║   ██║ ██║      █████╗   ██╔████╔██║
       ╚════██║ ██║   ██║ ██║      ██╔══╝   ██║╚██╔╝██║
       ███████║ ╚██████╔╝ ███████╗ ███████╗ ██║ ╚═╝ ██║
       ╚══════╝  ╚═════╝  ╚══════╝ ╚══════╝ ╚═╝     ╚═╝

       AI-native OS  ·  v0.1.0-step0

  '';

  # Script MOTD dinamico: stato servizi + endpoint + info utente.
  # Eseguito da update-motd al login interattivo.
  dynamicMotd = pkgs.writeShellScript "solem-motd-dynamic" ''
    set -u
    BOLD=$'\e[1m'
    DIM=$'\e[2m'
    GOLD=$'\e[38;5;179m'
    RED=$'\e[38;5;88m'
    GREEN=$'\e[32m'
    RESET=$'\e[0m'

    svc_status() {
      if ${pkgs.systemd}/bin/systemctl is-active --quiet "$1" 2>/dev/null; then
        echo "''${GREEN}● up''${RESET}"
      else
        echo "''${RED}○ down''${RESET}"
      fi
    }

    echo ""
    echo "''${BOLD}''${GOLD}  SOLEM''${RESET}  ''${DIM}—  AI-native OS''${RESET}"
    echo "  ''${DIM}$(date '+%A %d %B %Y · %H:%M')''${RESET}"
    echo ""
    echo "  ''${BOLD}Servizi''${RESET}"
    echo "    gavio.service      $(svc_status gavio)         ''${DIM}http://localhost:8000''${RESET}"
    echo "    solem-api.service  $(svc_status solem-api)     ''${DIM}http://localhost:8001''${RESET}"
    echo "    ollama.service     $(svc_status ollama)        ''${DIM}http://localhost:11434''${RESET}"
    echo "    docker.service     $(svc_status docker)"
    echo ""
    echo "  ''${BOLD}Strumenti''${RESET}"
    echo "    ''${GOLD}solem status''${RESET}       stato sistema completo"
    echo "    ''${GOLD}solem caps''${RESET}         capabilities scoperte"
    echo "    ''${GOLD}solem layers''${RESET}       stato dei 7 layer"
    echo "    ''${GOLD}solem pair''${RESET}         genera PIN per aggiungere device"
    echo ""
    echo "  ''${BOLD}Dashboard''${RESET}  ''${GOLD}http://localhost:8001''${RESET}    ''${DIM}(da host)''${RESET}"
    echo ""
  '';
in {
  # /etc/issue — banner statico pre-login (visibile prima di "login:")
  environment.etc."issue".text = banner;

  # MOTD post-login: messaggio statico minimal + invito a "solem status"
  users.motd = ''

      ╭──────────────────────────────────────────────────────────────╮
      │  SOLEM  ·  v0.1.0-step0                                      │
      │  digita 'solem status' per il quadro live del sistema        │
      ╰──────────────────────────────────────────────────────────────╯
  '';

  # MOTD dinamica via shell init (NON via PAM — quello sovrascrive auth).
  # Eseguito ad ogni shell interattiva di login (console + SSH).
  programs.bash.interactiveShellInit = ''
    # SOLEM dynamic MOTD — mostrato solo su login shell, una volta per sessione
    if [ -z "''${SOLEM_MOTD_SHOWN:-}" ] && shopt -q login_shell 2>/dev/null; then
      export SOLEM_MOTD_SHOWN=1
      ${dynamicMotd} 2>/dev/null || true
    fi
  '';
}
