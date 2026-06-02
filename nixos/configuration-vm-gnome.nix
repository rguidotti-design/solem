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
    ./modules/solem-branding-gnome.nix
    ./modules/solem-gtk-theme.nix
    ./modules/solem-welcome-zenity.nix
    ./modules/solem-gavio-chat-demo.nix
  ];

  solem.brandingGnome.enable = true;
  solem.gtkTheme.enable = true;
  solem.welcomeZenity.enable = true;
  solem.gavioChatDemo.enable = true;

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
    imagemagick  # per generare wallpaper runtime
  ];

  # Desktop files SOLEM/GAVIO visibili nel menu Activities
  environment.etc."xdg/applications/solem-status.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=SOLEM Status
    Comment=Friday HUD: stato sistema, security layers, GAVIO
    Exec=gnome-terminal -- bash -c "solem status; read -p 'Premi Enter per chiudere...'"
    Icon=preferences-system
    Terminal=false
    Categories=System;Monitor;
  '';

  environment.etc."xdg/applications/solem-demo.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=SOLEM Demo
    Comment=Walkthrough 10 capability SOLEM (Friday-style)
    Exec=gnome-terminal -- bash -c "solem-demo; read -p 'Premi Enter...'"
    Icon=preferences-system
    Terminal=false
    Categories=System;
  '';

  environment.etc."xdg/applications/gavio-ai.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=GAVIO AI
    Comment=Chat con GAVIO (l'AI personale di Ruben)
    Exec=gnome-terminal -- bash -c "echo '╭───────────────────────────────────────────╮'; echo '│  GAVIO — AI personale                     │'; echo '│  Stato: scaffolding pronto                │'; echo '│  Step 30/51: src GAVIO Python richiesto   │'; echo '│  Quando packaged: chat via prompt-filter  │'; echo '╰───────────────────────────────────────────╯'; echo; echo 'Per provare GAVIO oggi: gavio.theoryholding.com (cloud)'; echo 'Per integrarlo in SOLEM: docs/GAPS-VERO-OS.md'; read -p 'Premi Enter...'"
    Icon=face-smile
    Terminal=false
    Categories=AudioVideo;Education;
  '';

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
