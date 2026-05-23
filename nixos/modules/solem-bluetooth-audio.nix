{ config, pkgs, lib, ... }:

# SOLEM BLUETOOTH AUDIO — codecs premium (LDAC/aptX/AAC) + GUI per device.
#
# Single responsibility: SOLO config pipewire BT + codecs aggiuntivi
# (Hi-Res Audio via LDAC, gaming aptX-LL, Apple AAC). GUI Blueman.

let
  cfg = config.solem.bluetoothAudio;
in {
  options.solem.bluetoothAudio = {
    enable = lib.mkEnableOption "Bluetooth audio premium (LDAC + aptX + AAC)";

    powerOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    gui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Blueman GUI (system tray + manager)";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = cfg.powerOnBoot;
      settings = {
        General = {
          # Profilo audio dual: A2DP sink (musica) + HSP/HFP (chiamate)
          Enable = "Source,Sink,Media,Socket";
          # AutoConnect per device già paired
          AutoConnect = true;
          # KernelExperimental per LE Audio (BLE Audio + LC3 codec)
          KernelExperimental = true;
          # FastConnectable per ricollegamento veloce
          FastConnectable = true;
        };
      };
    };

    # PipeWire con tutti i codec BT
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
      extraConfig.pipewire."99-bluetooth-codecs" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;          # SBC eXtended Quality (FOSS)
          "bluez5.enable-msbc" = true;            # mSBC per HFP HD voice
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" "bap_source"
                              "hfp_hf" "hfp_ag" "hsp_hs" "hsp_ag" ];
          "bluez5.codecs" = [
            "sbc" "sbc_xq" "aac" "aptx" "aptx_hd" "aptx_ll" "aptx_ll_duplex"
            "ldac" "lc3plus_h1" "opus_05" "opus_05_71"
          ];
        };
      };
    };

    # Pacchetti
    environment.systemPackages = with pkgs; [
      bluez bluez-tools
      # Hi-Fi audio playback
      easyeffects   # equalizer + audio processing GUI
      pavucontrol
    ] ++ lib.optional cfg.gui blueman;

    services.blueman.enable = lib.mkIf cfg.gui true;
  };
}
