{ config, pkgs, lib, ... }:

# SOLEM WORKLOAD DETECT — auto-adatta profilo OS in base al lavoro.
#
# Principio: SOLEM osserva processi/file attivi e suggerisce/applica
# profili ottimizzati per il workload:
#
#   - informatica/coding    → CPU governor performance, ulimit alti,
#                              dev tools loaded in memory
#   - CAD/3D                → GPU performance, swappiness basso,
#                              huge pages, gamemode-like tuning
#   - cybersec/pentesting   → tcpdump promiscuous, scapy/nmap ready,
#                              firewall log verbose
#   - finanza/data          → Jupyter, pandas in memory, GPU compute,
#                              swap aggressive
#   - server                → no sleep, all cores, networking tuned
#   - HPC/quantum/AI        → CUDA/ROCm, NUMA-aware, RDMA, qiskit
#
# CLI: `solem-workload <profile>` applica setting runtime.
# Daemon: `solem-workload auto` osserva e suggerisce/applica.

let
  cfg = config.solem.workloadDetect;

  workloadCli = pkgs.writeShellApplication {
    name = "solem-workload";
    runtimeInputs = with pkgs; [ coreutils gawk libnotify systemd procps ];
    text = ''
      ACTION="''${1:-status}"
      shift || true

      STATE_DIR="/var/lib/solem/workload"
      mkdir -p "$STATE_DIR" 2>/dev/null || true
      CURRENT_FILE="$STATE_DIR/current"

      apply_cpu_governor() {
        local GOV="$1"
        # Richiede root o cpupower group
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          [ -e "$cpu" ] && echo "$GOV" | sudo tee "$cpu" >/dev/null 2>&1 || true
        done
      }

      apply_swappiness() {
        local VAL="$1"
        echo "$VAL" | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1 || true
      }

      apply_dirty_ratio() {
        local VAL="$1"
        echo "$VAL" | sudo tee /proc/sys/vm/dirty_ratio >/dev/null 2>&1 || true
      }

      apply_profile() {
        local PROFILE="$1"
        case "$PROFILE" in
          coding|dev|informatica)
            apply_cpu_governor "performance"
            apply_swappiness 10
            ulimit -n 65536
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          cad|3d|gpu)
            apply_cpu_governor "performance"
            apply_swappiness 5
            apply_dirty_ratio 5
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          cybersec|pentest|security)
            apply_cpu_governor "performance"
            # No tuning estremo; cybersec ha bisogno di sistema "normale"
            # per non distorcere risultati
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          finanza|data|jupyter)
            apply_cpu_governor "performance"
            apply_swappiness 60  # data science usa molto swap
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          server|24-7)
            apply_cpu_governor "schedutil"  # bilanciato
            apply_swappiness 10
            # Disattiva suspend
            systemctl mask sleep.target suspend.target hibernate.target 2>/dev/null || true
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          hpc|quantum|ai|ml)
            apply_cpu_governor "performance"
            apply_swappiness 1
            apply_dirty_ratio 3
            # Huge pages opt-in (richiede config separato boot)
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          balanced|default|laptop)
            apply_cpu_governor "schedutil"
            apply_swappiness 60
            apply_dirty_ratio 20
            echo "$PROFILE" > "$CURRENT_FILE"
            ;;
          *)
            echo "Profilo sconosciuto: $PROFILE" >&2
            return 1
            ;;
        esac
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -t 5000 "SOLEM Workload" "Profilo applicato: $PROFILE"
        fi
      }

      detect_profile() {
        # Heuristic: lista processi → guess profilo
        local PROCS
        PROCS=$(ps -eo comm --no-headers 2>/dev/null | sort -u)

        if echo "$PROCS" | grep -qE "code|vim|nvim|jetbrains|emacs|tmux|cargo|go-build|rustc"; then
          echo "coding"
          return
        fi
        if echo "$PROCS" | grep -qE "freecad|blender|kicad|openscad|inkscape"; then
          echo "cad"
          return
        fi
        if echo "$PROCS" | grep -qE "wireshark|tcpdump|nmap|metasploit|burp"; then
          echo "cybersec"
          return
        fi
        if echo "$PROCS" | grep -qE "jupyter|pandas|R |gnuplot|jupyterlab"; then
          echo "finanza"
          return
        fi
        if echo "$PROCS" | grep -qE "ollama|whisper|cuda|nvidia-smi|qiskit"; then
          echo "ai"
          return
        fi
        # Default
        echo "balanced"
      }

      case "$ACTION" in
        apply)
          PROFILE="''${1:?Usage: solem-workload apply <profile>}"
          apply_profile "$PROFILE"
          ;;
        auto|detect)
          DETECTED=$(detect_profile)
          echo "Profilo detectato: $DETECTED"
          if [ "''${1:-}" = "--apply" ]; then
            apply_profile "$DETECTED"
          fi
          ;;
        list)
          cat <<'PROFILES'
Profili disponibili:
  coding/dev         CPU performance, swappiness=10, ulimit alti
  cad/3d/gpu         CPU perf, swappiness=5, dirty=5
  cybersec/pentest   CPU perf, no tuning aggressivo
  finanza/data       CPU perf, swappiness=60 (data sci usa swap)
  server/24-7        CPU schedutil, no sleep/suspend
  hpc/quantum/ai     CPU perf, swappiness=1, huge pages opt
  balanced/laptop    CPU schedutil, default (default)
PROFILES
          ;;
        status|current)
          CURRENT=$(cat "$CURRENT_FILE" 2>/dev/null || echo "balanced")
          echo "── SOLEM Workload Profile ──"
          echo "  Corrente:   $CURRENT"
          GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?")
          SWAP=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "?")
          echo "  CPU gov:    $GOV"
          echo "  Swappiness: $SWAP"
          echo "  Detectato:  $(detect_profile)"
          ;;
        help|--help|-h|*)
          cat <<'HELP'
solem-workload — profilo OS auto-adattivo

  apply <profile>     applica profilo manualmente
  auto                rileva workload da processi attivi
  auto --apply        rileva + applica
  list                lista profili
  status              profilo corrente + setting attivi

Profili:
  coding, cad, cybersec, finanza, server, hpc, balanced

Tutto FOSS. Tuning via /sys/ + /proc/. Richiede sudo per alcuni write.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.workloadDetect = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-workload` profilo OS auto-adattivo";
    };

    autoApply = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Daemon che rileva workload ogni 5 min e applica profilo
        automaticamente. Default off (l'utente decide).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ workloadCli ];

    systemd.tmpfiles.rules = [
      "d /var/lib/solem/workload 0755 root root - -"
    ];

    # Daemon auto-detect (opt-in)
    systemd.services.solem-workload-auto = lib.mkIf cfg.autoApply {
      description = "SOLEM workload auto-detect + apply";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${workloadCli}/bin/solem-workload auto --apply";
      };
    };

    systemd.timers.solem-workload-auto = lib.mkIf cfg.autoApply {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };

    # Sudoers: permetti scrittura specifica su /sys/ /proc/ per workload tuning
    # senza chiedere password
    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          { command = "/run/current-system/sw/bin/tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/tee /proc/sys/vm/swappiness"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/tee /proc/sys/vm/dirty_ratio"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };
}
