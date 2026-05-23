{ config, pkgs, lib, ... }:

# SOLEM SECURITY ADVANCED — eBPF monitoring + IDS Suricata + Falco runtime.
#
# Single responsibility: SOLO orchestrare 3 tool sicurezza enterprise-grade
# opt-in:
#   - Falco: eBPF runtime threat detection (anomaly process exec, file
#            access sensitive, network exotic)
#   - Suricata: NIDS network intrusion detection (rules ET Open)
#   - eBPF tools: bpftrace, bcc, kubectl-trace
#
# Tutti FOSS. Costo: 0 € (vs Crowdstrike / SentinelOne enterprise).

let
  cfg = config.solem.securityAdvanced;
in {
  options.solem.securityAdvanced = {
    falco = {
      enable = lib.mkEnableOption "Falco runtime threat detection (eBPF)";
    };

    suricata = {
      enable = lib.mkEnableOption "Suricata IDS (rules ET Open)";
      interface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Interfaccia da monitorare";
      };
    };

    ebpfTools = lib.mkEnableOption "eBPF debugging tools (bpftrace, bcc, bpftool)";
  };

  config = lib.mkMerge [
    # Falco
    (lib.mkIf cfg.falco.enable {
      services.falco = {
        enable = true;
        rules = {
          "solem-rules" = ''
            - rule: Modifica file critici SOLEM
              desc: Avvisa se /etc/solem/* viene modificato fuori da nixos-rebuild
              condition: open_write and fd.directory startswith /etc/solem and not proc.name in (nixos-rebuild)
              output: SOLEM config modified (user=%user.name file=%fd.name proc=%proc.cmdline)
              priority: WARNING
          '';
        };
      };
    })

    # Suricata
    (lib.mkIf cfg.suricata.enable {
      services.suricata = {
        enable = true;
        settings = {
          af-packet = [{
            interface = cfg.suricata.interface;
            cluster-id = 99;
            cluster-type = "cluster_flow";
          }];
          rule-files = [
            "suricata.rules"   # default + ET Open
          ];
          outputs = [
            { fast = { enabled = true; filename = "fast.log"; }; }
            { eve-log = { enabled = true; filetype = "regular"; filename = "eve.json"; }; }
          ];
        };
      };
    })

    # eBPF tools
    (lib.mkIf cfg.ebpfTools {
      environment.systemPackages = with pkgs; [
        bpftrace bpftools
        bcc
        falco-driver-loader
        tshark           # Wireshark CLI
        wireshark        # GUI
      ];
      programs.wireshark.enable = true;
      users.users.gavio.extraGroups = lib.mkAfter [ "wireshark" ];
    })
  ];
}
