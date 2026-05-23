{ config, pkgs, lib, ... }:

# SOLEM SPID ITALIA — supporto CIE 3.0 + SPID + Tessera Sanitaria.
#
# Single responsibility: SOLO config smart card reader (PCSC) + tool
# specifici italiani (CIE 3.0 NFC, SPID provider login, Firma Digitale).
#
# Use case: login a INPS, Agenzia Entrate, Fascicolo Sanitario via CIE
# diretta dal browser SOLEM. Niente più Windows-only.
#
# 100% FOSS. Stack standard: pcscd + opensc + ccid + browser plugin CIE.

let
  cfg = config.solem.spidItalia;
in {
  options.solem.spidItalia = {
    enable = lib.mkEnableOption "Smart card italiano (CIE 3.0 + Firma Digitale + SPID)";

    enableCieReader = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Lettore CIE 3.0 via NFC USB (Identive, ACR, Bit4id)";
    };

    enableFirma = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Firma Digitale (PEC, contratti) via DikePro / ArubaSign";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Smart card services ──
    services.pcscd.enable = true;

    # OpenSC framework PKCS#11 + CCID drivers
    environment.systemPackages = with pkgs; [
      opensc           # framework smart card
      pcsc-tools       # pcsc_scan diagnostic
      pcsclite
    ] ++ lib.optionals cfg.enableCieReader [
      # Bridge ufficiale CIE non è in nixpkgs (closed-source IPZS).
      # Workaround: usa middleware open `libdigidocpp` o usa cie-middleware
      # da fork community.
      libdigidocpp
    ];

    # ── Browser config (Firefox PKCS#11 + Chromium NSS) ──
    # User deve aggiungere il modulo PKCS#11 manualmente:
    #   about:preferences#privacy → Security Devices → Load
    #   /run/current-system/sw/lib/opensc-pkcs11.so

    # ── Banner istruzioni ──
    environment.etc."solem/spid-italia.md".text = ''
      # SOLEM SPID Italia

      ## Hardware supportato
      - **CIE 3.0** (Carta Identità Elettronica): lettore NFC USB
        - Identive Cloud 4700F
        - ACR1252U-A1
        - Bit4id miniLector EVO
      - **Token USB** firma digitale (Aruba, Infocert, Namirial)
      - **Smart card** standard PKCS#11

      ## Setup primo uso
      1. Collega lettore USB
      2. Inserisci CIE/smart card
      3. Verifica: `pcsc_scan` deve vedere la carta
      4. Browser Firefox: about:preferences#privacy → Security Devices →
         Load → `/run/current-system/sw/lib/opensc-pkcs11.so`
      5. Vai su INPS/Agenzia Entrate, scegli "Entra con CIE"

      ## Firma Digitale
      Per firmare PDF: `solem-app install com.aruba.sign` (DikePro alt)
      oppure usa il browser dell'agenzia che ti emette il token.

      ## Privacy
      Tutto locale. SOLEM non vede mai il PIN; passa solo tra te,
      la smart card, e il sito (con TLS).
    '';

    # ── Polkit rule per gavio: accesso smart card senza prompt ──
    services.udev.extraRules = ''
      # Bit4id miniLector EVO
      SUBSYSTEM=="usb", ATTR{idVendor}=="072f", ATTR{idProduct}=="b100", TAG+="uaccess"
      # ACR1252U
      SUBSYSTEM=="usb", ATTR{idVendor}=="072f", ATTR{idProduct}=="223e", TAG+="uaccess"
      # Identive Cloud
      SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="5790", TAG+="uaccess"
    '';
  };
}
