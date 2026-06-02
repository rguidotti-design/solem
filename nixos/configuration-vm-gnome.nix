{ config, pkgs, lib, ... }:

# CONFIGURAZIONE VM GNOME — desktop GNOME che FUNZIONA in QEMU.
#
# Differenza da vm-desktop (Hyprland): GNOME ha rendering software
# robusto (llvmpipe fallback), greetd/GDM testato, funziona in QEMU
# senza GPU acceleration.

{
  imports = [
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
  ];

  # ── Desktop GNOME completo (Wayland + Xorg fallback) ──
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Auto-login user gavio per demo
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "gavio";

  # GNOME extra packages
  environment.systemPackages = with pkgs; [
    firefox
    gnome-terminal
    nautilus
    gnome-calculator
    gnome-system-monitor
    gnome-disk-utility
    gedit
  ];

  # Audio per QEMU
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # Identità
  networking.hostName = "solem-gnome-demo";
  system.stateVersion = "24.11";
  networking.networkmanager.enable = true;

  # Tool
  environment.shells = [ pkgs.bash ];
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  console.keyMap = "it";

  # QEMU: GPU virtio + RAM/cores per desktop
  virtualisation.vmVariant.virtualisation = {
    memorySize = lib.mkForce 4096;
    cores = lib.mkForce 4;
    qemu.options = [
      "-vga virtio"
      "-display gtk,gl=on"
    ];
  };

  # SSH per debug
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
}
