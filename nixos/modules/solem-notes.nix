{ config, pkgs, lib, ... }:

# SOLEM NOTES — note-taking locale FOSS (Logseq + Obsidian-compat).
#
# Single responsibility: SOLO installazione app + creazione vault default
# in ~/Documents/Notes con struttura zettelkasten ready.
#
# Apps FOSS:
#   - Logseq        → outliner markdown, plain-text, FOSS
#   - SilverBullet  → opzionale (server self-host, web access)
#   - Marktext      → editor markdown WYSIWYG
#
# 100% locale, costo 0 €. Compat Obsidian: vault dir markdown.

let
  cfg = config.solem.notes;
in {
  options.solem.notes = {
    enable = lib.mkEnableOption "Note-taking integrato (Logseq + Marktext)";

    silverbullet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "SilverBullet server self-host (porta 3030)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      logseq
      marktext
      pandoc  # export multi-formato
    ];

    # SilverBullet server (opzionale)
    systemd.services.silverbullet = lib.mkIf cfg.silverbullet {
      description = "SilverBullet — note-taking server self-host";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "gavio";
        WorkingDirectory = "/home/gavio/Documents/Notes";
        ExecStart = "${pkgs.silverbullet}/bin/silverbullet --port 3030 .";
        Restart = "on-failure";
      };
    };

    # Vault default zettelkasten-ready
    systemd.tmpfiles.rules = [
      "d /home/gavio/Documents/Notes              0755 gavio users - -"
      "d /home/gavio/Documents/Notes/journals     0755 gavio users - -"
      "d /home/gavio/Documents/Notes/pages        0755 gavio users - -"
      "d /home/gavio/Documents/Notes/assets       0755 gavio users - -"
      "f /home/gavio/Documents/Notes/README.md    0644 gavio users - -"
    ];
  };
}
