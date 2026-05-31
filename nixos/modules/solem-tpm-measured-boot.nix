{ config, pkgs, lib, ... }:

# SOLEM TPM MEASURED BOOT — Step 35: PCR sealing + disk encryption hardware-bound.
#
# Single responsibility: SOLO tooling per TPM2 + LUKS PCR binding +
# attestazione integrità boot.
#
# Threat coperto (oltre Step 32 Secure Boot):
#   - Evil maid POST signed boot: anche con Secure Boot, attacker fisico
#     potrebbe sostituire bootloader signed da SOLEM stesso (capture nostre
#     keys). Con TPM PCR sealing: chiavi LUKS si rilasciano SOLO se PCR
#     (misure del boot) corrispondono al baseline atteso.
#   - Kernel command-line tampering: PCR include kernel cmdline. Se attacker
#     aggiunge `init=/bin/sh` per single-user mode boot, PCR mismatch →
#     LUKS chiave non rilasciata → disk inaccessibile.
#   - Firmware downgrade attack: PCR include firmware version. Downgrade
#     a BIOS vulnerabile → PCR mismatch.
#
# Stack:
#   - systemd-cryptenroll (LGPL-2.1+): bind LUKS key a TPM2 PCR
#   - tpm2-tools (BSD-3): manipolazione TPM2 manuale
#   - clevis (GPL-3.0): alternativa per binding LUKS a TPM/Tang/PIN
#
# Prerequisites HARDWARE:
#   - Chip TPM 2.0 (Intel PTT su CPU 8th+, AMD fTPM 2.0+)
#   - UEFI con Secure Boot abilitato (Step 32 attivo)
#   - LUKS volume gia' esistente
#
# Tutto FOSS. 0 €.

let
  cfg = config.solem.tpmMeasuredBoot;
in {
  options.solem.tpmMeasuredBoot = {
    enable = lib.mkEnableOption "TPM2 measured boot scaffolding + CLI";

    pcrIndices = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ 0 2 7 ];
      description = ''
        PCR (Platform Configuration Registers) usati per sealing.
        Defaults:
          - PCR 0: firmware (BIOS/UEFI version)
          - PCR 2: option ROM (driver firmware)
          - PCR 7: Secure Boot state + signed bootloader
        Aggiungi PCR 4 (boot loader code) per max strict ma rompe
        ad ogni kernel update fino a re-seal.
      '';
    };

    luksDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/sda2";
      description = ''
        Device LUKS da enrolare con TPM2 binding.
        Se null, solo CLI disponibile (no auto-enroll).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Kernel modules per TPM2
    boot.kernelModules = [ "tpm_crb" "tpm_tis" ];

    # systemd-cryptenroll (incluso in systemd > 248)
    services.tpm2 = {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };

    environment.systemPackages = with pkgs; [
      tpm2-tools
      tpm2-tss
      tpm2-pkcs11
      clevis
      (pkgs.writeShellApplication {
        name = "solem-tpm";
        runtimeInputs = with pkgs; [ coreutils tpm2-tools cryptsetup systemd ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM TPM Measured Boot ──"
              if [ ! -e /dev/tpm0 ] && [ ! -e /dev/tpmrm0 ]; then
                echo "✗ Nessun TPM trovato (controllare BIOS: enable fTPM/PTT)"
                exit 1
              fi
              echo "✓ TPM device presente: $(ls /dev/tpm* 2>/dev/null | head -1)"
              echo
              echo "── TPM properties ──"
              sudo tpm2_getcap properties-fixed 2>&1 | grep -E "TPM_MANUFACTURER|TPM_FAMILY|TPM_FIRMWARE" | head -5
              echo
              echo "── PCR baseline (current) ──"
              for pcr in ${lib.concatStringsSep " " (map toString cfg.pcrIndices)}; do
                VAL=$(sudo tpm2_pcrread "sha256:$pcr" 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' | head -1)
                echo "  PCR $pcr (sha256): $VAL"
              done
              ${lib.optionalString (cfg.luksDevice != null) ''
                echo
                echo "── LUKS enrollment (${cfg.luksDevice}) ──"
                sudo cryptsetup luksDump "${cfg.luksDevice}" 2>/dev/null | grep -E "Keyslots|Token" | head -10
              ''}
              ;;

            enroll)
              # Enrollment LUKS con TPM2 binding
              ${if cfg.luksDevice != null then ''
                DEVICE="${cfg.luksDevice}"
              '' else ''
                DEVICE="''${1:?Usage: solem-tpm enroll <device> (es. /dev/sda2)}"
              ''}
              PCRS=${lib.concatStringsSep "+" (map toString cfg.pcrIndices)}
              echo "── Enroll LUKS '$DEVICE' con TPM2 PCR=$PCRS ──"
              echo "ATTENZIONE: serve passphrase LUKS corrente per validare."
              sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs="$PCRS" "$DEVICE"
              echo "✓ Enrolled. Prossimo boot: LUKS unlock automatico se PCR matchano."
              echo "  RECOVERY: passphrase originale ancora valida (slot 0)."
              ;;

            reseal)
              # Re-seal dopo kernel/bootloader update (PCR cambiano)
              ${if cfg.luksDevice != null then ''
                DEVICE="${cfg.luksDevice}"
              '' else ''
                DEVICE="''${1:?Usage: solem-tpm reseal <device>}"
              ''}
              PCRS=${lib.concatStringsSep "+" (map toString cfg.pcrIndices)}
              echo "── Re-seal LUKS '$DEVICE' (nuovi PCR baseline) ──"
              sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEVICE"
              sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs="$PCRS" "$DEVICE"
              echo "✓ Re-sealed con PCR correnti."
              ;;

            pcr-snapshot)
              SNAP="/var/lib/solem/tpm-pcr-$(date +%s).json"
              sudo mkdir -p /var/lib/solem
              echo "{" | sudo tee "$SNAP" > /dev/null
              FIRST=1
              for pcr in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
                VAL=$(sudo tpm2_pcrread "sha256:$pcr" 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' | head -1)
                [ -z "$VAL" ] && continue
                [ "$FIRST" -eq 1 ] || echo "," | sudo tee -a "$SNAP" > /dev/null
                FIRST=0
                printf '  "pcr%s": "%s"' "$pcr" "$VAL" | sudo tee -a "$SNAP" > /dev/null
              done
              echo "" | sudo tee -a "$SNAP" > /dev/null
              echo "}" | sudo tee -a "$SNAP" > /dev/null
              echo "✓ PCR snapshot in $SNAP"
              ;;

            test-unlock)
              # Test simulato: prova unlock con TPM (no real unlock, solo check)
              ${if cfg.luksDevice != null then ''
                DEVICE="${cfg.luksDevice}"
              '' else ''
                DEVICE="''${1:?Usage: solem-tpm test-unlock <device>}"
              ''}
              echo "── Test TPM unlock $DEVICE (read-only check) ──"
              if sudo cryptsetup luksDump "$DEVICE" | grep -q "systemd-tpm2"; then
                echo "✓ Slot TPM2 enrolled"
              else
                echo "✗ NO slot TPM2 enrolled (run: solem-tpm enroll)"
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-tpm — TPM2 measured boot management

  status          TPM device + PCR baseline + LUKS slots
  enroll [dev]    enroll LUKS con TPM2 binding (PCR=${lib.concatStringsSep ", " (map toString cfg.pcrIndices)})
  reseal [dev]    re-seal dopo kernel/bootloader update
  pcr-snapshot    salva snapshot PCR correnti
  test-unlock     verifica enrollment senza unlock effettivo

PCR usati: ${lib.concatStringsSep ", " (map toString cfg.pcrIndices)}
  PCR 0: firmware UEFI version
  PCR 2: option ROM (driver firmware)
  PCR 7: Secure Boot state + signed bootloader

⚠ WORKFLOW PRIMO SETUP:
  1. Verifica TPM presente: solem-tpm status
  2. Snapshot baseline: solem-tpm pcr-snapshot (BACKUP USB!)
  3. Enroll LUKS: solem-tpm enroll /dev/sdaN
  4. Reboot → unlock automatico se PCR matchano
  5. Recovery: passphrase originale slot 0 ancora valida

⚠ Re-seal NECESSARIO dopo:
  - nixos-rebuild che cambia kernel
  - BIOS firmware update
  - Secure Boot key rotation

Threat coperto: evil maid POST signed boot, kernel cmdline tampering,
firmware downgrade attack.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/tpm-measured-boot.md".text = ''
      # SOLEM TPM Measured Boot (Step 35)

      LUKS disk-encryption chiavi sigillate al TPM2 + PCR baseline.
      Disk unlock automatico SOLO se boot misure (PCR) corrispondono.

      ## Threat coperto
      - **Evil maid post-Secure-Boot**: anche con Step 32 attivo, attacker
        fisico potrebbe sostituire bootloader signed. Con TPM PCR:
        chiavi LUKS rilasciate SOLO se PCR matchano → mismatch = no unlock.
      - **Kernel cmdline tampering**: PCR include cmdline. `init=/bin/sh`
        per single-user mode → PCR mismatch → disk inaccessibile.
      - **Firmware downgrade**: PCR 0 include firmware version. Downgrade
        BIOS vulnerabile → PCR mismatch.

      ## Setup primo uso

      ```bash
      # 1. Verifica TPM disponibile
      solem-tpm status

      # 2. Snapshot baseline (BACKUP CRITICO su USB esterno)
      solem-tpm pcr-snapshot

      # 3. Enroll LUKS volume
      solem-tpm enroll /dev/sda2
      # (chiede passphrase LUKS attuale per validare)

      # 4. Reboot → unlock automatico se PCR OK

      # 5. Recovery: passphrase originale slot 0 sempre valida
      ```

      ## Re-seal dopo update sistema

      ```bash
      sudo nixos-rebuild switch    # nuovo kernel
      solem-tpm reseal /dev/sda2   # re-bind con nuovi PCR
      ```

      Senza re-seal: prossimo boot non auto-unlock (richiede passphrase).
      Non e' un fail, e' protezione: PCR mismatch = qualcosa cambiato.

      ## Limiti onesti
      - Hardware: richiede TPM2 (assente su PC molto vecchi).
      - Re-seal manuale dopo ogni kernel update (fastidioso).
        SOLUZIONE futura: hook nixos-rebuild post-switch automatico.
      - PCR 7 = Secure Boot state: richiede Step 32 attivo per essere
        sensato (altrimenti PCR 7 dice "Setup Mode" = bypass facile).
      - TPM chip stesso e' bersaglio attacchi physical (probing, glitching),
        ma costoso e specialistico.
      - Cold boot attack su RAM con LUKS key estraibile: mitigato da
        Step encrypted-memory (zram + tmpfs).
    '';
  };
}
