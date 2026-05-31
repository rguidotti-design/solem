{ config, pkgs, lib, ... }:

# SOLEM DM-VERITY — Step 28: kernel-level read-only verified filesystem.
#
# Single responsibility: SOLO scaffolding + CLI per dm-verity hash tree
# di /nix/store. Genera hash tree offline, abilita verifica runtime
# kernel-enforced.
#
# Threat coperto:
#   - Tampering offline /nix/store: attacker con accesso fisico modifica
#     binary in /nix/store/abc-foo/bin/X (es. trojanizza systemd).
#     Senza verity: prossimo boot esegue binary modificato.
#     Con verity: kernel verifica hash block-by-block. Mismatch → I/O error
#     → boot fail safe.
#   - Bit rot: corruption silenziosa disco. verity detecta corruption.
#   - Rootkit injection in binary firmati: rootkit modifica file → hash
#     verifica fail.
#
# NB: dm-verity richiede:
#   - /nix/store su partizione DEDICATA (non in / con altro)
#   - hash tree generato offline + salvato su partizione READ-ONLY
#   - boot tooling che monta verity prima di pivot root
#
# Per NixOS questo richiede systemd-repart o lustration via stage-1 init.
# Step 28 = SCAFFOLDING (CLI + doc). Implementazione completa = futura
# Step 28b con boot.initrd custom.
#
# Tutto FOSS (cryptsetup veritysetup GPL). 0 €.

let
  cfg = config.solem.dmVerity;
in {
  options.solem.dmVerity = {
    enable = lib.mkEnableOption "dm-verity scaffolding + CLI (NOT full enforcement yet)";

    targetDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-label/nix-store";
      description = ''
        Device che contiene /nix/store. Per Step 28 completo serve partizione
        dedicata. Default /dev/disk/by-label/nix-store (creabile manualmente).
      '';
    };

    hashDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-label/nix-verity-hash";
      description = ''
        Device che ospita il merkle hash tree. Tipicamente partizione
        piccola (~1% di targetDevice).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      cryptsetup
      (pkgs.writeShellApplication {
        name = "solem-verity";
        runtimeInputs = with pkgs; [ coreutils cryptsetup util-linux ];
        text = ''
          ACTION="''${1:-status}"
          shift || true

          TARGET="${cfg.targetDevice}"
          HASH="${cfg.hashDevice}"
          ROOT_HASH_FILE="/etc/solem/verity-root-hash"

          case "$ACTION" in
            status)
              echo "── SOLEM dm-verity ──"
              echo "Target: $TARGET"
              echo "Hash:   $HASH"
              echo
              if [ -e "$TARGET" ]; then
                echo "✓ Target device esiste"
              else
                echo "✗ Target device NON esiste (crea partizione + label nix-store)"
              fi
              if [ -e "$HASH" ]; then
                echo "✓ Hash device esiste"
              else
                echo "✗ Hash device NON esiste"
              fi
              echo
              echo "── Mapping attivi verity ──"
              sudo dmsetup ls --target verity 2>/dev/null || echo "(nessun verity device attivo)"
              if [ -f "$ROOT_HASH_FILE" ]; then
                echo
                echo "── Root hash registrato ──"
                cat "$ROOT_HASH_FILE"
              fi
              ;;

            generate)
              # Genera hash tree offline da targetDevice
              echo "── Generate verity hash tree ──"
              if [ ! -e "$TARGET" ]; then
                echo "ERROR: $TARGET non esiste"
                exit 1
              fi
              if [ ! -e "$HASH" ]; then
                echo "ERROR: $HASH non esiste (crea partizione dedicata)"
                exit 1
              fi
              echo "Computing hash tree (lento per filesystem grossi)..."
              sudo mkdir -p /etc/solem
              ROOT_HASH=$(sudo veritysetup format "$TARGET" "$HASH" | grep "Root hash:" | awk '{print $3}')
              echo "$ROOT_HASH" | sudo tee "$ROOT_HASH_FILE" > /dev/null
              sudo chmod 644 "$ROOT_HASH_FILE"
              echo "✓ Root hash: $ROOT_HASH"
              echo "  Salvato in $ROOT_HASH_FILE"
              echo "  ⚠ BACKUP CRITICO: senza root hash non puoi verificare!"
              ;;

            verify)
              # Apre verity device + verifica
              if [ ! -f "$ROOT_HASH_FILE" ]; then
                echo "ERROR: root hash mancante. Esegui: solem-verity generate"
                exit 1
              fi
              ROOT_HASH=$(cat "$ROOT_HASH_FILE")
              echo "Verify $TARGET con root hash $ROOT_HASH..."
              sudo veritysetup open "$TARGET" nix-store-verity "$HASH" "$ROOT_HASH"
              echo "✓ Verity device attivo: /dev/mapper/nix-store-verity"
              echo "  Mount con: mount -o ro /dev/mapper/nix-store-verity /mnt"
              ;;

            close)
              sudo veritysetup close nix-store-verity 2>&1
              echo "✓ Verity device chiuso"
              ;;

            check-integrity)
              # Test integrita': legge tutto il device e conta error
              echo "Reading entire $TARGET (slow)..."
              if [ -e /dev/mapper/nix-store-verity ]; then
                ERR=$(sudo dd if=/dev/mapper/nix-store-verity of=/dev/null bs=4M 2>&1 | grep -c "error" || true)
                if [ "$ERR" = "0" ]; then
                  echo "✓ Integrita' verificata: nessun blocco corrotto"
                else
                  echo "✗ TROVATI $ERR errori — filesystem TAMPERED"
                fi
              else
                echo "Verity device non aperto. Esegui: solem-verity verify"
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-verity — dm-verity hash tree management

  status            target/hash device + verity mappings attivi
  generate          calcola hash tree per targetDevice + salva root hash
  verify            apri verity device read-only verified
  close             chiudi verity mapping
  check-integrity   leggi tutto + conta error (tampering check)

⚠ ATTENZIONE: Step 28 e' SCAFFOLDING.
   Implementazione COMPLETA richiede:
   - /nix/store su PARTIZIONE DEDICATA al boot install
   - stage-1 initramfs custom che monta verity PRIMA di pivot root
   - root hash committato nel bootloader (anti-rollback)

   Per ora: CLI utility per generare/verificare. Workflow uso:
   1. Crea partizione dedicata /nix/store (label nix-store)
   2. Crea partizione hash piu' piccola (label nix-verity-hash)
   3. solem-verity generate  → calcola hash tree
   4. Copia /etc/solem/verity-root-hash su USB SAFE
   5. Manualmente: solem-verity verify + mount /mnt
   6. (Futuro) Step 28b: boot integration automatica

Threat coperto:
  - Tampering offline /nix/store (evil maid, fisical access)
  - Bit rot disco
  - Rootkit injection in binary
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/dm-verity.md".text = ''
      # SOLEM dm-verity (Step 28)

      Kernel-level read-only verified filesystem per /nix/store.

      ## Threat coperto
      - **Offline tampering**: attacker con accesso fisico modifica /nix/store.
      - **Bit rot**: corruption silenziosa disco.
      - **Rootkit injection**: rootkit modifica binary firmati.

      ## Stato Step 28: SCAFFOLDING

      Implementazione completa richiede boot integration custom:
      - /nix/store su partizione DEDICATA
      - stage-1 initramfs monta verity PRIMA di pivot root
      - root hash nel bootloader (anti-rollback)

      Step 28b futuro: boot integration automatica via boot.initrd.systemd
      + systemd-repart per partition setup auto.

      ## CLI disponibile

      ```
      solem-verity status            # device + mappings
      solem-verity generate          # calcola hash tree offline
      solem-verity verify            # apri verified device
      solem-verity check-integrity   # full scan tampering
      ```

      ## Workflow manuale (no auto-boot ancora)

      1. Crea partizione dedicata: `parted /dev/sdX mkpart primary 1G 50G label nix-store`
      2. Crea partizione hash: `parted /dev/sdX mkpart primary 50G 51G label nix-verity-hash`
      3. `solem-verity generate` → root hash salvato in /etc/solem/verity-root-hash
      4. **CRITICO**: copia root hash su USB SAFE (senza non recuperi)
      5. `solem-verity verify` + mount manual

      ## Limiti onesti
      - Boot integration mancante: serve initramfs custom. Step 28b TODO.
      - Hash tree static: ogni rebuild Nix richiede `solem-verity generate` nuovo.
      - Performance: ~1-3% overhead I/O read (verify ogni blocco).
      - Root hash su disco: se attacker modifica entrambi disk + hash file,
        bypass. Mitigato: root hash nel bootloader (Secure Boot signed).
    '';
  };
}
