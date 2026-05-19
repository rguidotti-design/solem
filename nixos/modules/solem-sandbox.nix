{ config, pkgs, lib, ... }:

let
  cfg = config.solem.sandbox;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM SANDBOX — primitives per isolamento processi
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO sandbox userspace.
  # Allineamento Prompt Master v4.0 sez. 1.4.
  #
  # Strumenti installati (l'AI/utente li usa via subprocess):
  #   - bubblewrap: container leggero (usato da Flatpak)
  #   - firejail: sandbox app desktop con profili
  #   - landlock: LSM kernel per filesystem restriction per processo
  #   - nsjail: alternativa container minimal
  #
  # NB: questi sono TOOL disponibili, NON applicati di default ai servizi core.
  # Per hardening servizi core vedi solem-secure.nix + M1.1 hardening systemd.

  options.solem.sandbox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa strumenti sandbox (bubblewrap, firejail, landlock, nsjail).";
    };

    landlockEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Abilita Landlock LSM (kernel ≥ 5.13).";
    };

    firejailDefaults = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          executable = lib.mkOption { type = lib.types.path; };
          profile = lib.mkOption { type = lib.types.path; };
        };
      });
      default = { };
      description = "App da wrappare automaticamente con firejail (es. firefox).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pacchetti sandbox base
    environment.systemPackages = with pkgs; [
      bubblewrap
      firejail
      nsjail
      # landlock-cli per debug
    ];

    # Firejail SUID wrapper opzionale
    programs.firejail.enable = true;
    programs.firejail.wrappedBinaries = cfg.firejailDefaults;

    # Landlock LSM nel kernel (parameter di boot)
    boot.kernelParams = lib.mkIf cfg.landlockEnable [
      "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
    ];

    # Manifest
    environment.etc."solem/sandbox-config.json".text = builtins.toJSON {
      bubblewrap = "available — usa: bwrap --bind / / cmd";
      firejail = "available — usa: firejail --net=none firefox";
      nsjail = "available — usa: nsjail --user 99999:99999 -- cmd";
      landlock = if cfg.landlockEnable then "enabled (kernel LSM)" else "disabled";
      lsm_stack = if cfg.landlockEnable then "landlock,lockdown,yama,integrity,apparmor,bpf" else "default";
      note = "Strumenti available a discrezione AI/utente. Default non-applicati ai servizi core (vedi M1.1 hardening).";
    };
  };
}
