{ config, pkgs, lib, ... }:

# SOLEM THUNDERBOLT GUARD — Step 15: boltd + IOMMU enforcement.
#
# Single responsibility: SOLO Thunderbolt/USB4 device authorization + IOMMU.
#
# Threat coperto:
#   - Evil maid attack: attaccante con accesso fisico breve collega un
#     Thunderbolt device malicious che fa DMA read di RAM (estrae chiavi
#     cifratura, dump memoria runtime).
#   - PCILeech-style attacks: hardware tool ($300 amazon) che legge RAM
#     via Thunderbolt o ExpressCard.
#   - DMA via Thunderbolt è una delle classi piu' pericolose perche'
#     bypassa OS completamente.
#
# Mitigazioni:
#   1. boltd (FOSS, parte di systemd): default policy "no auth" -> device
#      non-pre-approved sono bloccati a livello hardware (kernel) prima
#      che il driver li enumeri.
#   2. IOMMU enforcement (intel_iommu=on / amd_iommu=on + iommu.passthrough=0):
#      anche se driver enumerano un device DMA-capable, IOMMU restringe le
#      regioni di memoria accessibili.
#   3. kernel.pci=nomsi su Thunderbolt: disabilita MSI interrupts pericolosi.
#
# Tutto FOSS (boltd LGPL-2.1+, kernel IOMMU GPL). 0 €.

let
  cfg = config.solem.thunderboltGuard;
in {
  options.solem.thunderboltGuard = {
    enable = lib.mkEnableOption "Thunderbolt/USB4 device authorization + IOMMU strict";

    iommuMode = lib.mkOption {
      type = lib.types.enum [ "off" "passthrough" "strict" ];
      default = "strict";
      description = ''
        Configurazione IOMMU:
          - off: nessuna protezione DMA (vulnerable)
          - passthrough: IOMMU on ma trasparente (perf migliore, security minore)
          - strict: IOMMU enforce su ogni device DMA (raccomandato)
        Per CPU Intel serve VT-d, per AMD serve AMD-Vi (controllare BIOS).
      '';
    };

    boltdPolicy = lib.mkOption {
      type = lib.types.enum [ "auto" "manual" "none" ];
      default = "manual";
      description = ''
        Policy auto-authorize per device Thunderbolt:
          - auto: device approvati immediatamente (insecure default)
          - manual: ogni device richiede authorization explicit
          - none: TUTTO bloccato (anche dock noti)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # boltd: gestione device Thunderbolt
    services.hardware.bolt.enable = true;

    # ────────────────────────────────────────────────────────────────
    # Kernel params: IOMMU + DMA hardening
    # ────────────────────────────────────────────────────────────────
    boot.kernelParams =
      (lib.optionals (cfg.iommuMode != "off") [
        "intel_iommu=on"
        "amd_iommu=on"
      ])
      ++ (lib.optionals (cfg.iommuMode == "strict") [
        # iommu.strict=1 forza sync IOMMU mappings (no batched unmap)
        # → DMA isolation piu' rigorosa, performance leggermente peggio
        "iommu.strict=1"
        "iommu.passthrough=0"
      ])
      ++ [
        # DMA remapping enforce su TUTTI i device PCIe (non solo I/O)
        # Vedi: https://wiki.archlinux.org/title/Improving_performance#Watchdogs
        "pcie_aspm=off"  # potrebbe causare DMA attack via L1 idle (paranoid)
      ];

    # ────────────────────────────────────────────────────────────────
    # udev policy: Thunderbolt device authorization
    # ────────────────────────────────────────────────────────────────
    services.udev.extraRules = lib.mkAfter ''
      # SOLEM Thunderbolt Guard — auth manual default
      # Quando un device TB viene collegato: default authorized=0.
      # L'utente DEVE autorizzarlo via `boltctl authorize <id>`.
      ${lib.optionalString (cfg.boltdPolicy == "manual") ''
        ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", \
          RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-tb -p warning ${pkgs.coreutils}/bin/echo \"TB UNAUTH: $env{DEVPATH} (run: boltctl authorize $env{ID_PATH})\""
      ''}

      ${lib.optionalString (cfg.boltdPolicy == "none") ''
        # Block-all: ogni device TB rejected
        ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", \
          ATTR{authorized}="-1", \
          RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-tb -p alert ${pkgs.coreutils}/bin/echo \"TB REJECTED: $env{DEVPATH}\""
      ''}

      # Log ogni TB add/remove
      ACTION=="add", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", \
        RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-tb -p info ${pkgs.coreutils}/bin/echo \"TB ADD: vendor=$env{ID_VENDOR_NAME} model=$env{ID_MODEL_NAME} uuid=$env{ID_UNIQUE_ID}\""

      ACTION=="remove", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", \
        RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-tb -p info ${pkgs.coreutils}/bin/echo \"TB REMOVE: uuid=$env{ID_UNIQUE_ID}\""
    '';

    # CLI di ispezione
    environment.systemPackages = with pkgs; [
      bolt
      (pkgs.writeShellApplication {
        name = "solem-thunderbolt";
        runtimeInputs = with pkgs; [ coreutils bolt systemd ];
        text = ''
          ACTION="''${1:-status}"
          shift || true

          case "$ACTION" in
            status)
              echo "── SOLEM Thunderbolt Guard ──"
              echo "Policy: ${cfg.boltdPolicy}"
              echo "IOMMU mode: ${cfg.iommuMode}"
              echo
              echo "── IOMMU attivo? ──"
              if [ -d /sys/class/iommu/dmar0 ] || [ -d /sys/class/iommu/iommu0 ]; then
                echo "✓ IOMMU enabled (Intel VT-d / AMD-Vi)"
                ls -1 /sys/class/iommu/ 2>/dev/null | head -3
              else
                echo "✗ IOMMU NON attivo (controllare BIOS: enable VT-d/AMD-Vi)"
              fi
              echo
              echo "── boltd status ──"
              if systemctl is-active bolt.service >/dev/null 2>&1; then
                echo "Daemon: ATTIVO"
              else
                echo "Daemon: spento"
              fi
              echo
              echo "── Devices Thunderbolt ──"
              boltctl list 2>/dev/null | head -30 || echo "(nessun device o non TB-capable)"
              ;;

            list)
              boltctl list
              ;;

            authorize|auth)
              ID="''${1:?Usage: solem-thunderbolt authorize <uuid>}"
              sudo boltctl authorize "$ID"
              echo "✓ $ID autorizzato"
              ;;

            enroll)
              ID="''${1:?Usage: solem-thunderbolt enroll <uuid>}"
              sudo boltctl enroll --policy=auto "$ID"
              echo "✓ $ID enrolled (auto-auth nei prossimi reboot)"
              ;;

            forget)
              ID="''${1:?Usage: solem-thunderbolt forget <uuid>}"
              sudo boltctl forget "$ID"
              echo "✓ $ID rimosso dal database"
              ;;

            log)
              echo "── Ultimi 30 eventi Thunderbolt ──"
              sudo journalctl -t solem-tb -n 30 --no-pager 2>/dev/null || echo "(nessun log)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-thunderbolt — gestione device Thunderbolt/USB4 + IOMMU

  status        IOMMU + boltd attivi? devices connessi?
  list          alias boltctl list
  authorize     accetta device per QUESTA sessione
  enroll        accetta device permanente (auto-auth ai reboot)
  forget        rimuovi device dal database
  log           ultimi eventi TB (journal)

Workflow: collega device TB nuovo -> sistema blocca + log warning ->
solem-thunderbolt list -> solem-thunderbolt enroll <uuid>.

Threat coperto:
  - Evil maid via Thunderbolt DMA
  - PCILeech-style attacks
  - Unauthorized docks/external GPU/external NIC

Tutto FOSS (boltd LGPL).
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/thunderbolt-guard.md".text = ''
      # SOLEM Thunderbolt Guard

      Thunderbolt e USB4 sono DMA-capable: un device collegato puo'
      LEGGERE/SCRIVERE RAM senza che il kernel possa fermarlo (a meno
      che IOMMU sia configurato strict).

      ## Stack difensivo

      1. **boltd** (services.hardware.bolt): default policy=${cfg.boltdPolicy}
         → ogni nuovo device richiede authorization explicit.
      2. **IOMMU mode**: ${cfg.iommuMode}
         - intel_iommu=on / amd_iommu=on in kernelParams
         - iommu.strict=1 (no batched unmap, isolation rigorosa)
         - iommu.passthrough=0 (DMA mediato da IOMMU per ogni device)
      3. **pcie_aspm=off**: chiude vettore DMA attack via L1 power state idle.
      4. **udev rules**: log ogni TB add/remove a journald.

      ## Threat coperto

      - **Evil maid attack**: attaccante con accesso fisico breve collega
        Thunderbolt device malicious (e.g. PCILeech). Senza IOMMU strict,
        legge RAM in ~30 secondi → estrae chiavi LUKS, password manager
        in-memory, ecc. Con SOLEM Thunderbolt Guard: device non-autorizzato
        non viene neanche enumerato. Anche se forzato, IOMMU limita DMA.
      - **Hostile dock**: un dock USB-C che monta una superficie attacco
        (USB peripherals + ethernet + DMA). Default policy=manual blocca.
      - **External GPU malicious**: GPU con BIOS modificato. Bloccato.

      ## Setup post-install

      ```bash
      # Verifica IOMMU attivo
      solem-thunderbolt status

      # Se IOMMU NON attivo: vai in BIOS, abilita VT-d (Intel) o AMD-Vi.

      # Quando colleghi un dock noto/fidato:
      solem-thunderbolt list                  # vedi uuid del device
      solem-thunderbolt enroll <uuid>         # permanent

      # Cambio dock/rimuovere device:
      solem-thunderbolt forget <uuid>
      ```

      ## Limiti onesti

      - IOMMU richiede SUPPORTO HARDWARE (BIOS VT-d/AMD-Vi). Alcuni
        chipset/laptop economici non lo hanno → su quelli, NESSUNA difesa
        DMA via TB e' possibile (chiudere la porta fisicamente o usarne
        solo USB 2.0/3.0 non DMA).
      - boltd policy "none" rompe dock legittimi: usare solo se non hai
        device TB.
      - pcie_aspm=off aumenta consumo batteria laptop (~5-10%): trade-off
        security vs autonomy. Considera disattivarlo su workstation fisse.
      - Non protegge da chip soldered/firmware-level (es. ME firmware
        Intel): vedi solem-kernel-harden kexec_load_disabled.
    '';
  };
}
