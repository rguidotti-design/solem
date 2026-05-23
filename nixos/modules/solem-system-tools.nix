{ config, pkgs, lib, ... }:

# SOLEM SYSTEM TOOLS — utility sistema (disk, info, cleanup, hw test).
#
# Single responsibility: SOLO installazione tool sistema FOSS + CLI
# wrapper `solem-clean` per cleanup spazio disco.
#
# Tutto FOSS, costo 0 €.

let
  cfg = config.solem.systemTools;

  cleanCli = pkgs.writeShellApplication {
    name = "solem-clean";
    runtimeInputs = with pkgs; [ nix coreutils dust ];
    text = ''
      ACTION="''${1:-summary}"
      case "$ACTION" in
        summary|status)
          echo "── Disk usage summary ──"
          du -sh /nix/store 2>/dev/null | awk '{print "  /nix/store: " $1}'
          du -sh ~/.cache 2>/dev/null | awk '{print "  ~/.cache:   " $1}'
          du -sh /tmp 2>/dev/null | awk '{print "  /tmp:       " $1}'
          du -sh /var/log 2>/dev/null | awk '{print "  /var/log:   " $1}'
          echo
          echo "── Top consumers (~/) ──"
          dust -d 1 "$HOME" 2>/dev/null | head -15
          ;;
        gc|nix-gc)
          echo "Nix garbage collection..."
          sudo nix-collect-garbage -d
          ;;
        gc-old)
          DAYS="''${2:-30}"
          echo "Removing generations older than ''${DAYS} days..."
          sudo nix-collect-garbage --delete-older-than "''${DAYS}d"
          ;;
        cache)
          echo "Pulizia ~/.cache..."
          du -sh ~/.cache 2>/dev/null
          read -r -p "Confermi? [y/N]: " ans
          [[ "''${ans,,}" == "y" ]] && rm -rf ~/.cache/* && echo "Done"
          ;;
        thumbs)
          echo "Pulizia thumbnails..."
          rm -rf ~/.cache/thumbnails/* 2>/dev/null
          echo "Done"
          ;;
        logs)
          echo "Vacuum journald a 100MB..."
          sudo journalctl --vacuum-size=100M
          ;;
        all)
          "$0" gc
          "$0" cache
          "$0" thumbs
          "$0" logs
          ;;
        *)
          echo "solem-clean — pulizia sistema"
          echo
          echo "  solem-clean summary       riepilogo uso disco"
          echo "  solem-clean gc            nix-collect-garbage"
          echo "  solem-clean gc-old [N]    rimuovi generation > N giorni"
          echo "  solem-clean cache         pulisci ~/.cache"
          echo "  solem-clean thumbs        thumbnails cache"
          echo "  solem-clean logs          journald vacuum 100MB"
          echo "  solem-clean all           tutto in sequenza"
          ;;
      esac
    '';
  };
in {
  options.solem.systemTools = {
    enable = lib.mkEnableOption "System tools (disk usage, info, cleanup, hw test)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      cleanCli

      # Disk usage
      filelight   # KDE disk usage analyzer
      baobab      # GNOME disk usage analyzer
      ncdu        # ncurses du
      dust        # già in solem-system-monitor ma utile anche qui

      # System info
      cpu-x          # CPU-Z equivalent
      hardinfo2      # System info GUI
      neofetch       # ASCII info
      fastfetch      # Faster neofetch

      # Hardware test
      memtest86plus  # RAM test
      stress-ng      # Stress test CPU/mem/IO
      sysbench       # benchmark
      smartmontools  # SMART disk
      hdparm
      lm_sensors

      # Boot analysis
      bootchart2

      # Power
      tlp                # tools laptop power
      powerstat
    ];

    # lm_sensors auto-config
    hardware.sensor.iio.enable = true;
  };
}
