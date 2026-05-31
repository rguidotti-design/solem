{ config, pkgs, lib, ... }:

# SOLEM PERFORMANCE TUNING — Step 48: baseline benchmarks + tuning.
#
# Single responsibility: SOLO orchestrazione tweak performance opt-in
# + CLI di benchmarking per misurare baseline + regressioni.

let
  cfg = config.solem.performanceTuning;
in {
  options.solem.performanceTuning = {
    enable = lib.mkEnableOption "Performance tweaks + benchmarking CLI";

    profile = lib.mkOption {
      type = lib.types.enum [ "balanced" "performance" "powersave" "server" ];
      default = "balanced";
      description = ''
        Profilo tuning:
          - balanced: ondemand governor, smart defaults
          - performance: governor=performance, no power save
          - powersave: governor=powersave, aggressive sleep
          - server: throughput-oriented, no GUI optimizations
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ── Profilo BALANCED (default) ──
    (lib.mkIf (cfg.profile == "balanced") {
      powerManagement.cpuFreqGovernor = "ondemand";
      services.thermald.enable = true;
    })

    # ── Profilo PERFORMANCE ──
    (lib.mkIf (cfg.profile == "performance") {
      powerManagement.cpuFreqGovernor = "performance";
      powerManagement.scsiLinkPolicy = "max_performance";
      boot.kernel.sysctl = {
        "vm.swappiness" = 10;
        "vm.vfs_cache_pressure" = 50;
      };
    })

    # ── Profilo POWERSAVE ──
    (lib.mkIf (cfg.profile == "powersave") {
      powerManagement.cpuFreqGovernor = "powersave";
      services.tlp.enable = true;
      services.tlp.settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "power";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      };
    })

    # ── Profilo SERVER ──
    (lib.mkIf (cfg.profile == "server") {
      powerManagement.cpuFreqGovernor = "performance";
      boot.kernel.sysctl = {
        "vm.swappiness" = 1;
        "vm.dirty_ratio" = 60;
        "vm.dirty_background_ratio" = 30;
        "net.core.somaxconn" = 4096;
        "net.ipv4.tcp_max_syn_backlog" = 8192;
        "fs.file-max" = 1000000;
      };
    })

    # ── Common ──
    {
      environment.systemPackages = with pkgs; [
        sysbench iperf3 fio stress-ng htop
        (pkgs.writeShellApplication {
          name = "solem-bench";
          runtimeInputs = with pkgs; [ coreutils sysbench fio iperf3 systemd-analyze ];
          text = ''
            ACTION="''${1:-quick}"

            case "$ACTION" in
              quick)
                echo "── SOLEM Performance Baseline (quick, ~30s) ──"
                echo
                echo "── Boot time ──"
                systemd-analyze 2>&1 | head -5
                echo
                echo "── CPU single-core ──"
                sysbench cpu --threads=1 --time=5 run 2>&1 | grep -E "events|total time"
                echo
                echo "── Memory throughput ──"
                sysbench memory --memory-block-size=4K --time=5 run 2>&1 | grep -E "MiB/sec|operations"
                echo
                echo "── Disk read IOPS ──"
                fio --name=rand-read --rw=randread --bs=4k --size=100M --runtime=5 --time_based --filename=/tmp/fio.tmp 2>&1 | grep -E "iops|bw="
                rm -f /tmp/fio.tmp
                ;;

              boot)
                systemd-analyze
                echo
                echo "── Slowest services ──"
                systemd-analyze blame | head -15
                echo
                echo "── Critical chain ──"
                systemd-analyze critical-chain | head -20
                ;;

              cpu)
                sysbench cpu --threads="$(nproc)" --time=10 run
                ;;

              disk)
                fio --name=mixed --rw=randrw --rwmixread=70 --bs=4k --size=500M --runtime=10 --time_based --filename=/tmp/fio.tmp
                rm -f /tmp/fio.tmp
                ;;

              memory)
                sysbench memory --memory-block-size=1M --memory-total-size=10G run
                ;;

              network)
                echo "iperf3 server su localhost..."
                iperf3 -s -1 &
                sleep 1
                iperf3 -c 127.0.0.1 -t 5
                ;;

              save-baseline)
                FILE="/var/lib/solem/bench-baseline-$(date +%Y%m%d).txt"
                sudo mkdir -p /var/lib/solem
                solem-bench quick | sudo tee "$FILE"
                echo "✓ Baseline saved: $FILE"
                ;;

              help|--help|-h|*)
                cat <<'HELP'
solem-bench — performance benchmark

  quick           CPU + memory + disk + boot (30s)
  boot            systemd-analyze critical-chain
  cpu             sysbench CPU multi-thread
  disk            fio mixed 70/30 read/write
  memory          sysbench memory bandwidth
  network         iperf3 loopback
  save-baseline   salva snapshot per regression tracking
HELP
                ;;
            esac
          '';
        })
      ];
    }
  ]);
}
