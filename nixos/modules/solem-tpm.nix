{ config, pkgs, lib, ... }:

let
  cfg = config.solem.tpm;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM TPM — TPM 2.0 measured boot + key sealing
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO interazione con TPM2 hardware.
  # Allineamento Prompt Master v4.0 sez. 5.1.
  #
  # Usi:
  #   - measured boot (kernel + initrd + cmdline hashati nei PCR)
  #   - LUKS key sealing (passphrase auto-unseal se boot integro)
  #   - attestation per zero-trust mTLS

  options.solem.tpm = {
    enable = lib.mkEnableOption "TPM2 measured boot + tools (richiede hardware TPM2.0)";
  };

  config = lib.mkIf cfg.enable {
    # tpm2-abrmd: access broker resource manager
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;     # PKCS#11 provider per smart-card-like access
      tctiEnvironment.enable = true;
    };

    # Tool TPM2
    environment.systemPackages = with pkgs; [
      tpm2-tools           # tpm2_pcrread, tpm2_seal, ecc.
      tpm2-tss             # libreria + libreria abrmd
    ];

    # User gavio in gruppo tss per accesso TPM
    users.users.gavio.extraGroups = [ "tss" ];

    environment.etc."solem/tpm-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      access_broker = "tpm2-abrmd";
      pkcs11 = "available";
      cli_tools = [ "tpm2_pcrread" "tpm2_seal" "tpm2_unseal" "tpm2_createprimary" ];
      use_cases = [
        "measured boot (PCR 0-7 hash kernel+initrd+cmdline)"
        "LUKS key sealing (unseal automatico se boot integro)"
        "zero-trust attestation (Step 2+)"
      ];
    };
  };
}
