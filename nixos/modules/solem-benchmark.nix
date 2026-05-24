{ config, pkgs, lib, ... }:

# SOLEM BENCHMARK — `solem-bench` esegue suite performance FOSS.
#
# Single responsibility: SOLO CLI che lancia benchmark standard e
# pubblica risultati in /var/log/solem/bench/. Niente upload cloud.

let
  cfg = config.solem.benchmark;

  benchCli = pkgs.writeShellApplication {
    name = "solem-bench";
    runtimeInputs = with pkgs; [ sysbench stress-ng hyperfine fio coreutils gawk systemd ];
    text = ''
      ACTION="''${1:-all}"
      OUT="/var/log/solem/bench/$(date +%Y%m%d-%H%M%S)"
      sudo mkdir -p "$OUT"
      sudo chown "$USER:users" "$OUT"

      run_step() {
        local NAME="$1"; shift
        echo "── $NAME ──"
        "$@" 2>&1 | tee "$OUT/$NAME.log"
        echo ""
      }

      case "$ACTION" in
        cpu)
          run_step cpu-prime    sysbench cpu --threads="$(nproc)" --cpu-max-prime=20000 run
          ;;
        memory|mem)
          run_step mem-bench    sysbench memory --memory-block-size=1K --memory-total-size=10G run
          ;;
        disk|io)
          run_step disk-fio     fio --name=read --filename=/tmp/sol-bench --size=512M \
            --rw=read --bs=4k --runtime=10 --time_based --group_reporting
          rm -f /tmp/sol-bench
          ;;
        boot)
          run_step boot-blame   systemd-analyze blame
          run_step boot-critical systemd-analyze critical-chain
          ;;
        idle-ram)
          # Misura RAM idle dopo 60s di quiete
          sleep 60
          run_step idle-ram     free -h
          ;;
        all)
          solem-bench cpu
          solem-bench memory
          solem-bench disk
          solem-bench boot
          solem-bench idle-ram
          ;;
        report)
          if [ ! -d /var/log/solem/bench ]; then
            echo "Nessun benchmark eseguito. Lancia: solem-bench all"
            exit 1
          fi
          LAST=$(ls -1t /var/log/solem/bench/ | head -1)
          echo "── Ultimo benchmark: $LAST ──"
          for log in /var/log/solem/bench/"$LAST"/*.log; do
            echo "=== $(basename "$log") ==="
            tail -20 "$log"
            echo ""
          done
          ;;
        *)
          echo "solem-bench — performance benchmark FOSS"
          echo
          echo "  solem-bench cpu        sysbench CPU prime"
          echo "  solem-bench memory     sysbench RAM bandwidth"
          echo "  solem-bench disk       fio sequential read"
          echo "  solem-bench boot       systemd-analyze blame + critical-chain"
          echo "  solem-bench idle-ram   RAM idle dopo 60s"
          echo "  solem-bench all        tutti i benchmark"
          echo "  solem-bench report     mostra ultimi risultati"
          ;;
      esac
    '';
  };
in {
  options.solem.benchmark = {
    enable = lib.mkEnableOption "Suite benchmark performance FOSS (sysbench + fio + boot-analyze)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      benchCli
      sysbench
      stress-ng
      fio
      hyperfine        # micro-benchmark CLI
      iperf3           # rete
      glmark2          # GPU OpenGL
      vkmark           # GPU Vulkan
    ];

    # Crea dir log con permessi corretti al boot
    systemd.tmpfiles.rules = [
      "d /var/log/solem/bench 0755 root root - -"
    ];
  };
}
