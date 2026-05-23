{ config, lib, pkgs, ... }:

# SOLEM shell defaults — zsh + starship + aliases.
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 10000;
    initExtra = ''
      # SOLEM branding prompt fallback
      [[ -z "$STARSHIP_SHELL" ]] && PS1='%F{220}solem%f %F{244}$%f '
    '';
    shellAliases = {
      ll = "eza -lah --icons";
      ls = "eza --icons";
      cat = "bat";
      grep = "rg";
      find = "fd";
      gst = "git status";
      gd = "git diff";
      gp = "git pull";
      gco = "git checkout";
      gavio = "solem ai";
      "solem-help" = "solem help";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "[](#0B1426)[ SOLEM ](bg:#0B1426 fg:#D4A24A bold)[](fg:#0B1426) $directory$git_branch$git_status$character";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
    };
  };

  programs.git = {
    enable = true;
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "nvim";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    fastfetch    # neofetch successor con logo SOLEM custom
    btop
    htop
  ];
}
