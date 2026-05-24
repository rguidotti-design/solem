{ config, pkgs, lib, ... }:

# SOLEM AUDIO PRO — PipeWire low-latency + EasyEffects + RNNoise.
#
# Single responsibility: SOLO configurazione audio professionale FOSS:
# - PipeWire low-latency quanta=64/256 per studio recording
# - EasyEffects per filtri/EQ/compressor system-wide
# - RNNoise plugin per noise suppression voice
# - Helvum (GUI patch matrix PipeWire)
# - qpwgraph (alternativa Qt)

let
  cfg = config.solem.audioPro;
in {
  options.solem.audioPro = {
    enable = lib.mkEnableOption "Audio pro FOSS (PipeWire low-latency + EasyEffects + RNNoise)";

    lowLatency = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Quanta 64 (3ms@48kHz). Off di default (consuma più CPU).";
    };

    rnnoise = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Filtro RNNoise noise-suppression voice (per chiamate)";
    };

    easyeffects = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "EasyEffects GUI per EQ/compressor system-wide";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      jack.enable = true;
      wireplumber.enable = true;

      extraConfig.pipewire."92-low-latency" = lib.mkIf cfg.lowLatency {
        context.properties = {
          default.clock.rate = 48000;
          default.clock.quantum = 64;
          default.clock.min-quantum = 64;
          default.clock.max-quantum = 256;
        };
      };
    };

    # PipeWire deve essere preferito a PulseAudio (NixOS 24.11)
    hardware.pulseaudio.enable = lib.mkForce false;
    security.rtkit.enable = true;

    environment.systemPackages = with pkgs; lib.flatten [
      [
        helvum             # GUI patch matrix PipeWire (FOSS)
        qpwgraph           # alt Qt
        pavucontrol        # GUI mixer classico
        pulsemixer         # TUI mixer
        alsa-utils         # alsamixer
        playerctl          # MPRIS controller
      ]

      (lib.optionals cfg.easyeffects [
        easyeffects
      ])

      (lib.optionals cfg.rnnoise [
        rnnoise-plugin     # plugin LADSPA
        noise-suppression-for-voice
      ])
    ];

    # Users in audio group
    users.groups.audio = {};
  };
}
