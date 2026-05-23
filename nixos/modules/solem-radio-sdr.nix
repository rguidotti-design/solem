{ config, pkgs, lib, ... }:

# SOLEM RADIO/SDR — software-defined radio + ham radio 100% FOSS.
#
# Single responsibility: SOLO orchestrare driver e GUI SDR FOSS:
# - RTL-SDR / Airspy / HackRF driver (FOSS)
# - GQRX / SDRangel / CubicSDR GUI per ascolto
# - GNU Radio per scripting / decode segnali
# - Multimon-NG (POCSAG, FLEX, X10) FOSS
# - dump1090 ADSB (aerei) FOSS
# - Direwolf packet radio FOSS
# - Hamlib / FLDigi / FLrig per ham radio
#
# Hobby / ricerca / emergenza. Costo: 0 € (richiede dongle USB ~10 €).

let
  cfg = config.solem.radioSdr;
in {
  options.solem.radioSdr = {
    enable = lib.mkEnableOption "Stack SDR/Ham radio FOSS (RTL-SDR + GQRX + GNU Radio)";

    adsb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "dump1090-mutability — tracking aerei in tempo reale (ADSB)";
    };

    hamRadio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Ham radio (FLDigi + FLrig + Hamlib + Direwolf packet radio + JS8Call)";
    };

    pulsar = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Ricezione satelliti meteo + decode (gpredict + wxtoimg-alt)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        # Driver dongle
        rtl-sdr
        rtl-sdr-blog
        soapysdr-with-plugins
        soapyrtlsdr
        soapyhackrf
        hackrf

        # GUI SDR
        gqrx        # GUI classica
        cubicsdr    # alternativa pulita
        sdrangel    # potente (multi-modulo)
        sdrpp       # SDR++ moderno

        # Toolkit
        gnuradio
        gr-osmosdr

        # Decoding utility
        multimon-ng   # POCSAG/FLEX/X10/FAX
        rtl_433       # 433 MHz sensori meteo/case smart
        kalibrate-rtl # calibration

        # Spettro / monitor
        gnss-sdr      # GPS L1 demod FOSS
      ]

      (lib.optionals cfg.adsb [
        dump1090
        readsb
      ])

      (lib.optionals cfg.hamRadio [
        fldigi
        flrig
        flmsg
        hamlib
        direwolf
        js8call
        wsjtx          # FT8 / FT4 (popolare digital mode)
        chirp          # programming RTX
        cqrlog         # logbook ham
        gridtracker
        qsstv          # SSTV digital TV
      ])

      (lib.optionals cfg.pulsar [
        gpredict       # tracking satelliti
        # noaa-apt    # decode NOAA APT — non in nixpkgs stabile, segnaliamo
      ])
    ];

    # Permessi USB per RTL-SDR senza sudo
    services.udev.packages = with pkgs; [ rtl-sdr hackrf ];

    # Utenti che usano SDR vanno in "plugdev"
    users.groups.plugdev = {};

    # Modulo kernel: blacklist driver TV DVB-T per liberare RTL-SDR
    boot.blacklistedKernelModules = [
      "dvb_usb_rtl28xxu"   # liberato per RTL-SDR
    ];
  };
}
