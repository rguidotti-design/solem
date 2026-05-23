{ config, pkgs, lib, ... }:

# SOLEM PRIVACY TOOLS — GPG + 2FA + password gen + disk wipe.
#
# Single responsibility: SOLO installazione tool privacy/crypto FOSS +
# CLI helper `solem-priv` per quick action.
#
# Tutto FOSS, costo 0 €.

let
  cfg = config.solem.privacyTools;

  privCli = pkgs.writeShellApplication {
    name = "solem-priv";
    runtimeInputs = with pkgs; [ gnupg oath-toolkit pwgen diceware coreutils ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        gpg-key|create-key)
          echo "Generazione chiave GPG (interactive)..."
          gpg --full-generate-key
          ;;
        gpg-list|keys)
          gpg --list-keys
          ;;
        gpg-export)
          KEYID="''${2:?Usage: solem-priv gpg-export <KEYID>}"
          gpg --export --armor "$KEYID"
          ;;
        password|pass|pwgen)
          LEN="''${2:-24}"
          pwgen -s -y "$LEN" 1
          ;;
        password-easy|easy)
          # Diceware-style: 6 parole memorizzabili
          diceware -n "''${2:-6}"
          ;;
        totp|2fa)
          # Calcola TOTP dato il secret base32
          SECRET="''${2:?Usage: solem-priv totp <BASE32-secret>}"
          oathtool --base32 --totp "$SECRET"
          ;;
        encrypt-file)
          SRC="''${2:?Usage: solem-priv encrypt-file <input> [recipient]}"
          RECIPIENT="''${3:-$USER}"
          gpg --encrypt --recipient "$RECIPIENT" --armor "$SRC"
          echo "Output: $SRC.asc"
          ;;
        decrypt-file)
          SRC="''${2:?Usage: solem-priv decrypt-file <input.asc>}"
          gpg --decrypt "$SRC"
          ;;
        wipe-file)
          # Sovrascrittura sicura (3 pass) prima del delete
          SRC="''${2:?Usage: solem-priv wipe-file <input>}"
          echo "Wipe sicuro di $SRC (3 pass)..."
          shred -uvz -n 3 "$SRC"
          ;;
        wipe-disk)
          DISK="''${2:?Usage: solem-priv wipe-disk /dev/sdX}"
          echo "ATTENZIONE: cancella TUTTO da $DISK"
          read -r -p "Digita YES per confermare: " ans
          [[ "$ans" == "YES" ]] || { echo "Annullato"; exit 1; }
          sudo nwipe "$DISK"
          ;;
        *)
          echo "solem-priv — privacy + crypto toolkit"
          echo
          echo "  GPG:"
          echo "    solem-priv gpg-key                    crea coppia chiavi"
          echo "    solem-priv gpg-list                   lista chiavi"
          echo "    solem-priv gpg-export <KEYID>         export pubkey ASCII"
          echo "    solem-priv encrypt-file <f> [recip]"
          echo "    solem-priv decrypt-file <f.asc>"
          echo
          echo "  Password:"
          echo "    solem-priv password [N]               random N char (default 24)"
          echo "    solem-priv easy [N]                   diceware N parole (memorizzabile)"
          echo
          echo "  2FA TOTP:"
          echo "    solem-priv totp <BASE32-secret>       calcola codice 6-digit"
          echo
          echo "  Wipe:"
          echo "    solem-priv wipe-file <f>              shred sicuro 3 pass"
          echo "    solem-priv wipe-disk /dev/sdX         nwipe disco intero (CARICA)"
          ;;
      esac
    '';
  };
in {
  options.solem.privacyTools = {
    enable = lib.mkEnableOption "Privacy + crypto tools (GPG + 2FA + pwgen + wipe)";

    yubikey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Supporto YubiKey/FIDO2 hardware key";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      privCli

      # GPG
      gnupg
      pinentry-gtk2
      gnupg-pkcs11-scd

      # 2FA TOTP
      oath-toolkit
      authenticator        # GTK4 GUI per TOTP

      # Password generation
      pwgen
      diceware
      apg
      keepassxc

      # Disk wipe / secure delete
      nwipe
      coreutils  # shred

      # File encryption
      age            # alternativa moderna a GPG
      rage

      # FIDO2 / hardware keys
      libfido2

    ] ++ lib.optionals cfg.yubikey [
      yubikey-manager
      yubikey-manager-qt
      yubikey-personalization
      yubikey-personalization-gui
    ];

    # YubiKey udev rules
    services.udev.packages = lib.mkIf cfg.yubikey (with pkgs; [
      yubikey-personalization
      libfido2
    ]);
    services.pcscd.enable = lib.mkIf cfg.yubikey true;

    # GPG agent
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-gtk2;
    };
  };
}
