{ config, pkgs, lib, ... }:

# SOLEM HW JUST WORKS — sane defaults per "hardware funziona OOTB".
#
# Single responsibility: SOLO un setup di defaults che attiva
# automaticamente quello che serve per un'esperienza desktop "just works"
# stile Windows/macOS.
#
# Tutto opt-in (default true ma controlled). Componenti:
# - PipeWire low-latency
# - Bluetooth + A2DP audio
# - Brightness key (light)
# - Power profiles + thermald
# - mDNS Avahi (printer/scanner discovery)
# - Auto-mount USB
# - Webcam/mic permissions standard
# - fwupd LVFS

let
  cfg = config.solem.hwJustWorks;
in {
  options.solem.hwJustWorks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Sane defaults per hardware desktop "just works":
        audio, bluetooth, brightness, power, mDNS discovery, fwupd.
        Default off per minimal CI; attivare su sistema utente reale.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ── AUDIO: PipeWire ──────────────────────────────────────────────
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    services.pulseaudio.enable = lib.mkForce false;
    security.rtkit.enable = true;

    # ── BLUETOOTH: A2DP audio ────────────────────────────────────────
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Enable = "Source,Sink,Media,Socket";
    };

    # ── BRIGHTNESS keys (sysfs + acpid) ──────────────────────────────
    programs.light.enable = true;

    # ── POWER: profiles-daemon (Linux laptop standard) ───────────────
    services.power-profiles-daemon.enable = true;
    services.thermald.enable = lib.mkDefault true;
    services.upower.enable = true;

    # ── mDNS: Avahi (printer/scanner/AirPlay discovery) ──────────────
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    # ── Auto-mount USB ───────────────────────────────────────────────
    services.udisks2.enable = true;
    services.gvfs.enable = true;

    # ── Firmware update via LVFS ─────────────────────────────────────
    services.fwupd.enable = true;

    # ── Firmware redistribuibile (Wi-Fi/BT/GPU FOSS) ────────────────
    hardware.enableRedistributableFirmware = true;

    # ── CPU microcode (Intel + AMD auto) ─────────────────────────────
    hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

    # ── Input devices ────────────────────────────────────────────────
    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
        clickMethod = "clickfinger";
      };
    };

    # ── Sensori (auto-rotate, ambient light) ─────────────────────────
    hardware.sensor.iio.enable = true;

    # ── Pacchetti utility hardware ───────────────────────────────────
    environment.systemPackages = with pkgs; [
      usbutils       # lsusb
      pciutils       # lspci
      smartmontools  # SMART SSD
      lm_sensors     # temperature CPU
      brightnessctl  # brightness CLI
      pavucontrol    # GUI audio mixer
      blueman        # GUI Bluetooth
    ];

    # ── Permission groups standard ───────────────────────────────────
    users.groups.video = {};
    users.groups.audio = {};
    users.groups.input = {};
    users.groups.scanner = {};
  };
}
