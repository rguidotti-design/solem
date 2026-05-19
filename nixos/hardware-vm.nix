{ config, pkgs, modulesPath, ... }:

{
  imports = [
    # Profilo NixOS per guest QEMU: kernel modules virtio, agent, ecc.
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Bootloader: GRUB su disco virtio (vda)
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  boot.growPartition = true;
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_blk" "virtio_net" "virtio_scsi" "9p" "9pnet_virtio"
  ];

  # Configurazione speciale per `nix run .#vm` (NixOS build-in VM testing).
  # NB: il percorso "source" è il path host. Su WSL2 Ubuntu il path Windows
  # c:\Users\guido\Desktop\gavio diventa /mnt/c/Users/guido/Desktop/gavio.
  # Se lanci con `nix run` da WSL, lascialo così. Da Linux puro, adatta.
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;       # 4 GB RAM
      cores = 4;               # 4 vCPU
      diskSize = 20000;        # 20 GB disco
      # IMPORTANTE: graphics=false (headless).
      # WSL2 QEMU GUI è instabile (display backend non sempre disponibile).
      # L'UI dell'utente è la dashboard navy nel BROWSER HOST a fullscreen:
      # http://localhost:8001 → SOLEM Desktop visibile.
      # La VM gira invisibile in background. Console seriale per debug.
      graphics = false;

      # Shared folder: la cartella GAVIO sull'host appare in /opt/gavio nella VM
      sharedDirectories.gavio = {
        source = "/mnt/c/Users/guido/Desktop/gavio";
        target = "/opt/gavio";
      };

      # Backend SOLEM (solem_api/) montato in /opt/solem-backend
      sharedDirectories.solem-backend = {
        source = "/mnt/c/Users/guido/Desktop/solem/backend";
        target = "/opt/solem-backend";
      };

      # Flake SOLEM (l'intera dir) montato in /opt/solem-flake
      # → permette `nixos-rebuild switch --flake /opt/solem-flake#solem-vm`
      # da dentro la VM (usato da /solem/system/rebuild API).
      sharedDirectories.solem-flake = {
        source = "/mnt/c/Users/guido/Desktop/solem";
        target = "/opt/solem-flake";
      };

      # Port forwarding: accesso a GAVIO/SOLEM/SSH dal browser/terminale host
      forwardPorts = [
        { from = "host"; host.port = 8000; guest.port = 8000; }  # GAVIO API
        { from = "host"; host.port = 8001; guest.port = 8001; }  # SOLEM API + Dashboard
        { from = "host"; host.port = 2222; guest.port = 22; }    # SSH
      ];
    };
  };
}
