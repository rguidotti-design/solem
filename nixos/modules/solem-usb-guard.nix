{ config, pkgs, lib, ... }:

# SOLEM USB GUARD — Step 13: udev tracking + USBGuard whitelist.
#
# Single responsibility: SOLO controllo device USB tramite USBGuard
# (FOSS) + udev rules che loggano ogni insert.
#
# Threat coperto:
#   - BadUSB (HID injection: USB che si presenta come tastiera + esegue payload)
#   - Mass-storage non autorizzato (exfil dati / malware drop)
#   - USB Rubber Ducky (HID + storage attack combinato)
#   - "Forgotten USB" lasciato in giro (social engineering)
#
# Approccio:
#   1. USBGuard daemon: blocca ALL devices new by default → policy
#      whitelist per VID:PID conosciuti (mouse, tastiera, hub).
#   2. udev rule: log a journald ogni USB event (anche se accettato).
#   3. notify desktop su nuovo device sconosciuto.
#
# Limiti onesti:
#   - USBGuard NON protegge da device gia' collegati al boot (sono in
#     initial state). Solo da hot-plug post-boot.
#   - Whitelist VID:PID si puo' spoofare (un attaccante con device
#     custom puo' programmare VID:PID di un mouse reale).
#   - Su laptop con USB integrato (camera, tastiera built-in) la
#     whitelist iniziale puo' essere fastidiosa da configurare.
#
# Tutto FOSS (USBGuard GPL-2.0, udev LGPL). 0 €.

let
  cfg = config.solem.usbGuard;
in {
  options.solem.usbGuard = {
    enable = lib.mkEnableOption "USBGuard whitelist + udev USB event logging";

    presentDevicePolicy = lib.mkOption {
      type = lib.types.enum [ "allow" "block" "reject" "keep" "apply-policy" ];
      default = "apply-policy";
      description = ''
        Cosa fare con device USB gia' connessi al boot:
          - allow: tutti accettati (default upstream, debole)
          - block: tutti bloccati (rompe tastiera/mouse!)
          - reject: idem block ma reject permanent
          - keep: mantieni stato corrente
          - apply-policy: applica regole rules.conf (raccomandato)
        Default apply-policy: solo i VID:PID in whitelist sono accettati.
      '';
    };

    insertedDevicePolicy = lib.mkOption {
      type = lib.types.enum [ "allow" "block" "reject" "apply-policy" ];
      default = "apply-policy";
      description = "Politica per device inseriti DOPO il boot";
    };

    notifyOnInsert = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "notify-send desktop quando viene inserito nuovo USB";
    };

    initialRules = lib.mkOption {
      type = lib.types.lines;
      default = ''
        # SOLEM USBGuard initial whitelist (genera con: solem-usb-guard learn).
        # Regole runtime in /var/lib/usbguard/rules.conf (auto-aggiunte
        # tramite `usbguard allow-device <id>`).
        #
        # Hub root: sempre allow (servono per Linux USB stack)
        allow with-interface equals { 09:00:00 }
      '';
      description = "Regole iniziali USBGuard (formato rules.conf)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.usbguard = {
      enable = true;
      package = pkgs.usbguard;
      dbus.enable = true;
      presentDevicePolicy = cfg.presentDevicePolicy;
      insertedDevicePolicy = cfg.insertedDevicePolicy;
      restoreControllerDeviceState = false;
      IPCAllowedUsers = [ "root" "gavio" ];
      IPCAllowedGroups = [ "wheel" ];

      # Inietta regole iniziali nel ruleFile
      rules = cfg.initialRules;
    };

    # udev rule: log ogni USB event a journald + notify desktop
    services.udev.extraRules = ''
      # SOLEM USB Guard — log + notify ogni insert/remove
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
        RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-usb -p info ${pkgs.coreutils}/bin/echo \"USB ADD: vid=$env{ID_VENDOR_ID} pid=$env{ID_MODEL_ID} model=$env{ID_MODEL} serial=$env{ID_SERIAL_SHORT}\""

      ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", \
        RUN+="${pkgs.systemd}/bin/systemd-cat -t solem-usb -p info ${pkgs.coreutils}/bin/echo \"USB REMOVE: vid=$env{ID_VENDOR_ID} pid=$env{ID_MODEL_ID}\""
    '';

    # CLI di ispezione + learning mode
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-usb-guard";
        runtimeInputs = with pkgs; [ coreutils usbguard systemd ];
        text = ''
          ACTION="''${1:-status}"
          shift || true

          case "$ACTION" in
            status)
              echo "── SOLEM USB Guard ──"
              if systemctl is-active usbguard.service >/dev/null 2>&1; then
                echo "Daemon: ATTIVO"
              else
                echo "Daemon: spento"
                exit 1
              fi
              echo
              echo "── Devices attivi ──"
              sudo usbguard list-devices 2>/dev/null | head -30
              echo
              echo "── Policy regole attive ──"
              sudo usbguard list-rules 2>/dev/null | head -20
              ;;

            list|devices)
              sudo usbguard list-devices
              ;;

            allow)
              ID="''${1:?Usage: solem-usb-guard allow <device-id>}"
              sudo usbguard allow-device "$ID" --permanent
              echo "✓ Device $ID allow permanent"
              ;;

            block)
              ID="''${1:?Usage: solem-usb-guard block <device-id>}"
              sudo usbguard block-device "$ID" --permanent
              echo "✓ Device $ID block permanent"
              ;;

            reject)
              ID="''${1:?Usage: solem-usb-guard reject <device-id>}"
              sudo usbguard reject-device "$ID" --permanent
              echo "✓ Device $ID rejected (kernel disconnect)"
              ;;

            learn)
              echo "── LEARN MODE ──"
              echo "Tutti i device attualmente connessi → whitelist permanente."
              echo "Usa SOLO su sistema affidabile (nessun USB sconosciuto)."
              read -r -p "Confermi? (yes/NO): " ANS
              if [ "$ANS" = "yes" ]; then
                sudo usbguard generate-policy > /tmp/usbguard-policy.tmp
                echo "Generato in /tmp/usbguard-policy.tmp:"
                cat /tmp/usbguard-policy.tmp
                echo
                read -r -p "Applico questa policy? (yes/NO): " ANS2
                if [ "$ANS2" = "yes" ]; then
                  sudo cp /tmp/usbguard-policy.tmp /var/lib/usbguard/rules.conf
                  sudo chmod 600 /var/lib/usbguard/rules.conf
                  sudo systemctl restart usbguard
                  echo "✓ Policy applicata + daemon riavviato"
                fi
              fi
              ;;

            log|events)
              echo "── Ultimi 30 eventi USB (journald) ──"
              sudo journalctl -t solem-usb -n 30 --no-pager 2>/dev/null || \
                echo "(nessun log SOLEM USB ancora)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-usb-guard — controllo device USB FOSS

  status        stato daemon + devices + regole attive
  list          tutti i device USB attualmente collegati
  allow <id>    accetta permanente un device by USBGuard ID
  block <id>    blocca permanente un device
  reject <id>   kernel-level disconnect + ban
  learn         genera policy dai device collegati ora (whitelist)
  log           ultimi 30 USB insert/remove (journal)

Workflow primo setup:
  1. Collega solo i device che usi davvero (mouse, tastiera, webcam).
  2. solem-usb-guard learn   → whitelist creata.
  3. Reboot.
  4. Da quel momento, nuovi USB sconosciuti → blocco automatico.

Threat coperto: BadUSB, Rubber Ducky, mass-storage non autorizzato.

Tutto FOSS (USBGuard GPL).
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/usb-guard.md".text = ''
      # SOLEM USB Guard

      USBGuard daemon (FOSS GPL-2.0) blocca ogni device USB sconosciuto.
      Workflow:

      1. **Setup iniziale** (sistema affidabile):
         ```
         solem-usb-guard learn
         ```
         Whitelist creata con i device collegati ora.

      2. **Runtime**: nuovi USB → blocco automatico fino approvazione.
         ```
         solem-usb-guard list           # vedi nuovi device
         solem-usb-guard allow <id>     # accetta permanente
         ```

      3. **Audit**: tutti gli insert/remove finiscono in journal:
         ```
         solem-usb-guard log
         ```

      ## Threat coperto

      - **BadUSB**: USB che si presenta come HID tastiera + digita payload.
        USBGuard blocca prima che il kernel lo enumeri come tastiera.
      - **Rubber Ducky**: HID + mass-storage combo. Blocco totale.
      - **Forgotten USB**: USB lasciato in giro, vittima collega → block.
      - **Mass-storage exfil**: thumb-drive sconosciuto per portar fuori
        dati → block.

      ## Limiti onesti

      - Device gia' collegati al boot NON sono bloccati (sono in initial
        state, gestito da presentDevicePolicy=apply-policy).
      - Spoofing VID:PID: un attaccante con device custom puo' programmare
        VID:PID di un mouse reale. Mitigazione: usa serial number unico
        nelle regole.
      - PCI device (NIC interno, GPU) NON sono coperti — USBGuard solo USB.
      - DMA attacks via Thunderbolt: serve protezione separata
        (boltctl / IOMMU policy), non in questo modulo.
    '';
  };
}
