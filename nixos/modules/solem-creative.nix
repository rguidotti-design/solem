{ config, pkgs, lib, ... }:

# SOLEM CREATIVE — stack creativo completo (foto + video + audio + 3D + design).
#
# Single responsibility: SOLO installazione bundle creator pro per chi
# fa foto/video/musica/3D, alternativa Adobe Creative Cloud.

let
  cfg = config.solem.creative;
in {
  options.solem.creative = {
    photo = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Foto: Darktable + GIMP + Krita + RawTherapee + digiKam";
    };

    video = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Video: Kdenlive + Shotcut + OBS + HandBrake + ffmpeg";
    };

    audio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Audio: Audacity + Ardour + LMMS + Hydrogen + Carla";
    };

    threed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "3D: Blender + FreeCAD + OpenSCAD + MeshLab + KiCad";
    };

    design = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Design: Inkscape + Scribus + Krita + Boxy SVG";
    };
  };

  config = lib.mkIf (cfg.photo || cfg.video || cfg.audio || cfg.threed || cfg.design) {
    environment.systemPackages = with pkgs; lib.flatten [
      (lib.optionals cfg.photo [
        darktable rawtherapee digikam gimp krita
        exiftool imagemagick graphicsmagick
      ])
      (lib.optionals cfg.video [
        kdenlive shotcut obs-studio handbrake
        ffmpeg-full mediainfo-gui
        flowblade
      ])
      (lib.optionals cfg.audio [
        audacity ardour lmms hydrogen
        carla qsynth
        helvum                     # PipeWire patchbay GUI
        easyeffects
        musescore                  # spartito
        muse-sounds-manager
      ])
      (lib.optionals cfg.threed [
        blender freecad openscad meshlab
        kicad
        wings
        librecad
      ])
      (lib.optionals cfg.design [
        inkscape scribus krita
        # Boxy SVG via flatpak
        font-manager
        fontforge
      ])
    ];

    # Audio low-latency setup per pro
    services.pipewire = lib.mkIf cfg.audio {
      enable = true;
      audio.enable = true;
      jack.enable = true;          # JACK pro-grade per audio production
      extraConfig.pipewire."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 256;
          "default.clock.min-quantum" = 256;
          "default.clock.max-quantum" = 256;
        };
      };
    };

    # Realtime kit per Ardour (low-latency audio)
    security.rtkit.enable = lib.mkIf cfg.audio true;
    users.users.gavio.extraGroups = lib.mkIf cfg.audio (lib.mkAfter [ "audio" ]);
  };
}
