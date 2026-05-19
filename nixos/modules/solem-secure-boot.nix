{ config, pkgs, lib, ... }:

let
  cfg = config.solem.secureBootLanzaboote;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM SECURE BOOT — Lanzaboote scaffold
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO Secure Boot via Lanzaboote.
  # Allineamento Prompt Master v4.0 sez. 5.1.
  #
  # Lanzaboote sostituisce systemd-boot con stub UEFI firmato.
  # Permette di usare chiavi UEFI utente (no Microsoft).
  #
  # Setup richiede:
  #   1. UEFI hardware (no BIOS legacy)
  #   2. systemd-boot abilitato come baseline
  #   3. Setup mode UEFI per enrollare chiavi custom
  #   4. Generazione chiavi via sbctl
  #   5. Input "lanzaboote" nel flake.nix
  #
  # Procedura completa: vedi docs/SECURE_BOOT.md (da creare Step 1+ bare-metal).

  options.solem.secureBootLanzaboote = {
    enable = lib.mkEnableOption "Lanzaboote Secure Boot (richiede UEFI + chiavi utente)";

    pkiBundle = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl";
      description = "Directory chiavi PKI (generate da sbctl).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Assertion: serve flake input
    assertions = [{
      assertion = builtins.hasAttr "lanzaboote" config;
      message = ''
        solem.secureBootLanzaboote.enable = true richiede input "lanzaboote".
        Aggiungi al flake:
          inputs.lanzaboote.url = "github:nix-community/lanzaboote/v0.4.2";
        Procedura completa setup chiavi:
          1. sudo sbctl create-keys
          2. (reboot) BIOS → Setup Mode
          3. sudo sbctl enroll-keys --microsoft  # tieni MS per dual-boot opzionale
          4. nixos-rebuild switch
          5. sbctl verify (deve mostrare tutti i binari "signed")
      '';
    }];

    # NB: la config reale `boot.lanzaboote.*` attiva solo con input flake disponibile

    environment.systemPackages = with pkgs; [ sbctl ];

    environment.etc."solem/secure-boot-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      pki_bundle = cfg.pkiBundle;
      provider = "Lanzaboote";
      cli_tool = "sbctl";
      microsoft_keys = "raccomandato per dual-boot (sbctl enroll-keys --microsoft)";
      verification = "sbctl verify";
    };
  };
}
