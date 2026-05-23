{ config, pkgs, lib, ... }:

# SOLEM CRASH REPORTER — coredump + analisi locale, ZERO upstream.
#
# Single responsibility: SOLO catturare crash sistema (systemd-coredumpd)
# + persistere in /var/lib/solem/crashes/ + chiedere a GAVIO un'analisi
# del backtrace (opt-in). NIENTE invio a server esterni, mai.
#
# Differenza vs Windows error reporter / macOS CrashReporter:
#   - 100% locale
#   - Nessun upload automatico
#   - Backtrace + journal salvato in /var/lib/solem/crashes/<timestamp>.json
#   - L'API /solem/crashes legge da lì

let
  cfg = config.solem.crashReporter;
in {
  options.solem.crashReporter = {
    enable = lib.mkEnableOption "Crash reporter locale (zero telemetria remota)";

    maxStorageMB = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = "Massimo storage core dumps (MB)";
    };

    maxCoreSize = lib.mkOption {
      type = lib.types.str;
      default = "256M";
      description = "Max size singolo core dump";
    };

    askGavio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Chiedi a GAVIO un'analisi dei crash al primo accesso /crashes (opt-in)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── systemd-coredump configurato ──
    systemd.coredump = {
      enable = true;
      extraConfig = ''
        Storage=external
        Compress=yes
        ProcessSizeMax=${cfg.maxCoreSize}
        ExternalSizeMax=${cfg.maxCoreSize}
        MaxUse=${toString cfg.maxStorageMB}M
        KeepFree=2G
      '';
    };

    # ── Director: /var/lib/solem/crashes ──
    systemd.tmpfiles.rules = [
      "d /var/lib/solem/crashes 0750 root systemd-coredump - -"
    ];

    # ── Hook: ogni nuovo coredump → JSON metadata in /var/lib/solem/crashes ──
    systemd.services."solem-crash-hook@" = {
      description = "SOLEM crash hook — salva metadata + backtrace per %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "solem-crash-hook" ''
          set -euo pipefail
          PID="$1"
          UID="$2"
          OUT="/var/lib/solem/crashes/$(date -u +%Y%m%dT%H%M%S)-pid$PID.json"

          {
            echo '{'
            echo "  \"timestamp\": \"$(date -u -Iseconds)\","
            echo "  \"pid\": $PID,"
            echo "  \"uid\": $UID,"
            echo "  \"backtrace\": $(${pkgs.coreutils}/bin/coreutils --version | head -1 | ${pkgs.jq}/bin/jq -R .),"
            echo "  \"journal_excerpt\": $(${pkgs.systemd}/bin/journalctl -p err --since '5 minutes ago' --no-pager | head -50 | ${pkgs.jq}/bin/jq -Rs .)"
            echo '}'
          } > "$OUT"
        '';
      };
    };

    # ── Banner che spiega ──
    environment.etc."solem/crash-reporter.md".text = ''
      # SOLEM Crash Reporter

      I crash di sistema (segfault, abort, OOM) sono catturati da
      systemd-coredumpd e salvati in /var/lib/solem/crashes/.

      ## Filosofia
      - 100% locale, niente upload
      - Storage cap ${toString cfg.maxStorageMB} MB (vecchi rotated)
      - Singolo core max ${cfg.maxCoreSize}

      ## API
      GET /solem/crashes              lista ultimi crash
      GET /solem/crashes/{id}/raw     core dump (gz)
      POST /solem/crashes/{id}/analyze   GAVIO analizza backtrace (opt-in)
    '';
  };
}
