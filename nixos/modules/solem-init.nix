{ config, pkgs, lib, ... }:

# SOLEM INIT — installa solem-init + solem-welcome + auto-launch primo boot.
#
# Single responsibility: SOLO packaging script + hook bashrc + tmpfiles.
# La logica vive negli script bash.
#
# Comandi installati:
#   solem-init       → wizard configurazione (6 domande)
#   solem-welcome    → first-boot orchestrator (banner + TTS + lancia init)
#   solem-doc        → apre USER-GUIDE.md

let
  initScript = pkgs.writeShellApplication {
    name = "solem-init";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../../scripts/solem-init.sh;
  };

  welcomeScript = pkgs.writeShellApplication {
    name = "solem-welcome";
    runtimeInputs = with pkgs; [ coreutils sudo ];
    text = builtins.readFile ../../scripts/solem-welcome.sh;
  };

  # solem-doc apre USER-GUIDE.md con il pager appropriato
  docScript = pkgs.writeShellApplication {
    name = "solem-doc";
    runtimeInputs = with pkgs; [ coreutils less ];
    text = ''
      DOC="/etc/solem/USER-GUIDE.md"
      if [ ! -f "$DOC" ]; then
        echo "USER-GUIDE.md non installato. Vedi:"
        echo "  https://github.com/rguidotti-design/solem/blob/main/docs/USER-GUIDE.md"
        exit 1
      fi
      if command -v glow >/dev/null 2>&1; then
        glow "$DOC"
      elif command -v mdcat >/dev/null 2>&1; then
        mdcat "$DOC" | less -R
      else
        less "$DOC"
      fi
    '';
  };
in {
  environment.systemPackages = [ initScript welcomeScript docScript ];

  # Directory /etc/solem deve esistere per onboarding.json
  systemd.tmpfiles.rules = [
    "d /etc/solem 0755 root root - -"
  ];

  # User guide accessibile da `solem-doc`
  environment.etc."solem/USER-GUIDE.md".source = ../../docs/USER-GUIDE.md;

  # ── Auto-launch solem-welcome al primo login (gavio user) ──
  # Lo aggiungiamo a bashrc/zshrc; lo script esce subito se onboarding già fatto.
  programs.bash.interactiveShellInit = ''
    # SOLEM welcome auto-launch al primo boot
    if [ -z "''${SOLEM_WELCOME_DONE:-}" ] && \
       [ ! -f /etc/solem/onboarding.json ] && \
       [ -t 1 ] && \
       [ "$(id -un)" = "gavio" ]; then
      export SOLEM_WELCOME_DONE=1
      solem-welcome 2>/dev/null || true
    fi
  '';

  # MOTD breve (se welcome saltato)
  environment.etc."issue.solem".text = ''

       ╔═══════════════════════════════════════════════╗
       ║    SOLEM — AI-native OS                       ║
       ║    Primo boot? Esegui:  solem-welcome         ║
       ║    Manuale:             solem-doc             ║
       ╚═══════════════════════════════════════════════╝

  '';
}
