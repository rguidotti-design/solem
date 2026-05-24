{ config, pkgs, lib, modulesPath, ... }:

# Hardware VM (QEMU guest).
#
# IMPORTANTE: sharedDirectories per i path WSL2 dell'utente sono in un
# file separato (hardware-vm-local.nix, gitignored) per non rompere la
# CI GitHub Actions che non ha quei path.

{
  imports = [
    # Profilo NixOS per guest QEMU: kernel modules virtio, agent, ecc.
    (modulesPath + "/profiles/qemu-guest.nix")

    # Overlay locale opzionale (sharedDirectories WSL2). Se il file non
    # esiste (es. su CI), Nix lo ignora silenziosamente.
  ] ++ lib.optional
    (builtins.pathExists ./hardware-vm-local.nix)
    ./hardware-vm-local.nix;

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

  # VM defaults (no shared folders — quelli sono in hardware-vm-local.nix)
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;       # 4 GB RAM
      cores = 4;               # 4 vCPU
      diskSize = 20000;        # 20 GB disco
      graphics = false;        # headless (WSL2-friendly)

      # Port forwarding base
      forwardPorts = [
        { from = "host"; host.port = 8000; guest.port = 8000; }  # GAVIO API
        { from = "host"; host.port = 8001; guest.port = 8001; }  # SOLEM API
        { from = "host"; host.port = 2222; guest.port = 22; }    # SSH
      ];
    };
  };
}
