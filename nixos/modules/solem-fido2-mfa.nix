{ config, pkgs, lib, ... }:

# SOLEM FIDO2 MFA — Step 18: hardware MFA via Yubikey/SoloKey/NitroKey.
#
# Single responsibility: SOLO configurare PAM per richiedere FIDO2 token
# come secondo fattore di autenticazione su sudo + login + ssh + display
# manager.
#
# Threat coperto:
#   - Password leak: anche con password rubata, attaccante senza HW token
#     non puo' loggare.
#   - Phishing: FIDO2 fa challenge-response cryptografico bound al device;
#     non puo' essere phisheato (a differenza di OTP/TOTP).
#   - Remote keylogger: chiave privata rimane in HW token, mai trasmessa.
#
# Hardware supportato (tutti FOSS firmware o aperti):
#   - YubiKey 5 (proprietario hw, FIDO2 open standard)
#   - SoloKey (FOSS firmware completo)
#   - NitroKey (FOSS firmware)
#   - Token Linux usbarmory (FOSS)
#
# Tutto FOSS lato software (libfido2 BSD, pam_u2f BSD, Linux-PAM BSD).

let
  cfg = config.solem.fido2Mfa;
in {
  options.solem.fido2Mfa = {
    enable = lib.mkEnableOption "FIDO2 hardware MFA su sudo + login + ssh";

    services = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "sudo" "login" "sshd" "su" "polkit-1" ]);
      default = [ "sudo" ];
      description = ''
        Quali servizi PAM richiedono FIDO2 token:
          - sudo: tutti i sudo richiedono touch token
          - login: console login (TTY) richiede token
          - sshd: SSH login (anche con key) richiede touch token aggiuntivo
          - su: switch user richiede token
          - polkit-1: azioni elevate GUI richiedono token

        Default solo "sudo" perche' meno invasivo. Aggiungi altri
        man mano che hai familiarita' con il workflow.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "required" "sufficient" ];
      default = "required";
      description = ''
        Modalita' auth:
          - required: FIDO2 token + password (entrambi)
          - sufficient: FIDO2 token DA SOLO basta (no password)
        Default "required" (true MFA).
      '';
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log debug pam_u2f a syslog (per troubleshoot)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # Package libfido2 + pam_u2f + udev rules per device access
    # ────────────────────────────────────────────────────────────────
    services.pcscd.enable = true;  # smart card daemon (alcuni token CCID)
    services.udev.packages = with pkgs; [
      yubikey-personalization
      libu2f-host
    ];

    # PAM module pam_u2f abilitato sui servizi richiesti
    security.pam.services = lib.genAttrs cfg.services (service: {
      u2fAuth = true;
    });

    # ────────────────────────────────────────────────────────────────
    # System-wide config (alternativa a per-user ~/.config/Yubico/u2f_keys)
    # ────────────────────────────────────────────────────────────────
    security.pam.u2f = {
      enable = true;
      control = cfg.mode;
      settings = {
        cue = true;  # mostra "Please touch the device" all'utente
        debug = cfg.debug;
        # authfile = "/etc/u2f-mappings";  # opt-in: setup system-wide
      };
    };

    # CLI helper
    environment.systemPackages = with pkgs; [
      libfido2
      yubikey-manager
      yubico-pam
      (pkgs.writeShellApplication {
        name = "solem-fido2";
        runtimeInputs = with pkgs; [ coreutils libfido2 yubikey-manager pam_u2f ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM Fido2 MFA ──"
              echo "Mode: ${cfg.mode}"
              echo "Services: ${lib.concatStringsSep ", " cfg.services}"
              echo
              echo "── Token rilevati ──"
              if command -v fido2-token >/dev/null 2>&1; then
                fido2-token -L 2>/dev/null || echo "(nessuno collegato)"
              else
                ykman list 2>/dev/null || echo "(yubikey-manager non disponibile)"
              fi
              echo
              echo "── Mapping registrato per utente ──"
              for U in $(getent passwd | awk -F: '$3 >= 1000 {print $1}'); do
                if [ -f "/home/$U/.config/Yubico/u2f_keys" ]; then
                  echo "  $U: $(wc -l < "/home/$U/.config/Yubico/u2f_keys") chiavi"
                fi
              done
              ;;

            register|enroll)
              echo "── Registra FIDO2 token per utente $USER ──"
              echo "Inserisci il token nella USB. Touch quando lampeggia."
              echo
              mkdir -p ~/.config/Yubico
              pamu2fcfg -u "$USER" >> ~/.config/Yubico/u2f_keys
              echo
              echo "✓ Registrato. Test: sudo true"
              ;;

            test)
              echo "Test FIDO2 MFA. Dovrebbe chiedere touch del token..."
              sudo true && echo "✓ Auth riuscita" || echo "✗ Auth fallita"
              ;;

            backup)
              echo "── Backup u2f_keys (importante per recovery!) ──"
              DEST="''${1:?Usage: solem-fido2 backup <dest-path>}"
              if [ -f "$HOME/.config/Yubico/u2f_keys" ]; then
                cp "$HOME/.config/Yubico/u2f_keys" "$DEST"
                chmod 600 "$DEST"
                echo "✓ u2f_keys salvato in $DEST"
                echo "  ⚠ Copialo su USB esterno SUBITO!"
              else
                echo "Nessun u2f_keys registrato (esegui prima: solem-fido2 register)"
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-fido2 — hardware FIDO2 MFA (Yubikey/SoloKey/NitroKey)

  status        token collegati + utenti registrati
  register      enroll token per l'utente corrente (touch richiesto)
  test          test auth sudo (deve chiedere touch)
  backup <dst>  salva u2f_keys mapping (backup essenziale!)

Workflow primo setup:
  1. Inserisci token nella USB
  2. solem-fido2 status      → verifica detect
  3. solem-fido2 register    → enroll (touch durante registrazione)
  4. solem-fido2 backup /media/usb-backup/u2f_keys
  5. solem-fido2 test        → conferma funziona

Token consigliati FOSS:
  - SoloKey (firmware open source completo)
  - NitroKey (firmware FOSS, prodotto in Germania)
  - YubiKey 5 (firmware proprietario MA standard FIDO2 aperto)

⚠ ATTENZIONE: senza token o backup u2f_keys, sei LOCKED OUT dal sistema.
  Sempre tenere 2 token (primario + backup) e copia u2f_keys su USB.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/fido2-mfa.md".text = ''
      # SOLEM FIDO2 MFA

      Hardware MFA via Yubikey/SoloKey/NitroKey su servizi PAM critici.

      ## Mode: ${cfg.mode}
      ## Services protetti: ${lib.concatStringsSep ", " cfg.services}

      ## Threat coperto
      - **Password leak**: anche se rubata, attaccante senza HW token NON entra.
      - **Phishing**: FIDO2 e' challenge-response cryptografico bound al device.
        Non phishabile (a differenza di TOTP).
      - **Remote keylogger**: chiave privata MAI esce dal HW token.
      - **Replay attack**: ogni auth e' una sessione unica (anti-replay built-in).

      ## Hardware FOSS consigliato
      - **SoloKey** (firmware FOSS completo)
      - **NitroKey** (firmware FOSS, made in Germany)
      - **YubiKey 5** (firmware proprietario MA standard FIDO2 aperto)

      ## ⚠⚠⚠ RECOVERY CRITICO ⚠⚠⚠

      Senza token o backup u2f_keys, sei **LOCKED OUT** completamente.

      Setup minimo per safety:
        1. 2 token fisici (primario + backup, registrati entrambi)
        2. Copia u2f_keys su USB esterno (NON sul sistema!)
        3. Stampa u2f_keys su carta (recovery paranoid)
        4. Recovery USB con NixOS bootable + accesso fisico al disco

      ## Setup primo uso

      ```bash
      solem-fido2 status                # verifica token detect
      solem-fido2 register              # enroll primario (touch)
      # Ripeti per token backup
      solem-fido2 backup /media/usb/u2f_keys
      solem-fido2 test                  # conferma funziona
      ```

      ## Limiti onesti
      - SSH key-only NON e' MFA: chiunque ha la chiave entra. Aggiungendo
        FIDO2 a sshd, anche con chiave SSH serve touch del token (true 2FA).
      - Polkit (GUI elevation) include richiesta touch token. UX su laptop
        senza key-card slot e' fastidiosa.
      - sudo + touch costante puo' essere fastidioso. Considera:
        Defaults timestamp_timeout=15 in sudoers (sudo NOPASSWD 15min).
      - Hardware perso = locked out. Backup essenziale.
    '';
  };
}
