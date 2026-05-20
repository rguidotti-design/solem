{ config, pkgs, lib, ... }:

# SOLEM CLI EXTRA — installa `solemctl` (complemento bash di `solem` py).
#
# Single responsibility: SOLO packaging dello script bash + bash completion.
# Tutto il routing logic è in scripts/solemctl.sh.
#
# `solem` (Python, ricco): status/identity/pair/panic.
# `solemctl` (bash, leggero): ai/search/ext/update/backup/crashes/profile.

let
  solemctl = pkgs.writeShellApplication {
    name = "solemctl";
    runtimeInputs = with pkgs; [ curl jq sudo coreutils ];
    text = builtins.readFile ../../scripts/solemctl.sh;
  };
in {
  environment.systemPackages = [ solemctl ];

  # Bash completion
  environment.etc."bash_completion.d/solemctl".text = ''
    _solemctl() {
      local cur prev opts
      COMPREPLY=()
      cur="''${COMP_WORDS[COMP_CWORD]}"
      prev="''${COMP_WORDS[COMP_CWORD-1]}"
      opts="profile search ai backup update ext extensions crashes help"

      if [[ ''${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "''${opts}" -- ''${cur}) )
        return 0
      fi

      case "''${prev}" in
        update)
          COMPREPLY=( $(compgen -W "check apply rollback history status" -- ''${cur}) )
          ;;
        ext|extensions)
          COMPREPLY=( $(compgen -W "list avail install enable disable uninstall" -- ''${cur}) )
          ;;
        profile)
          COMPREPLY=( $(compgen -W "minimal developer creator server desktop" -- ''${cur}) )
          ;;
      esac
    }
    complete -F _solemctl solemctl
  '';
}
