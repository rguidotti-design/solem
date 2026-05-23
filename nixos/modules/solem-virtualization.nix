{ config, pkgs, lib, ... }:

# SOLEM VIRTUALIZATION — VM management + Distrobox toolbox-like.
#
# Single responsibility: SOLO config virtualizzazione user-friendly:
#   - libvirtd + KVM + QEMU
#   - virt-manager GUI
#   - Distrobox (run altre distro come container persistenti)
#   - Toolbox (Fedora-style)
#   - Looking Glass (per VFIO GPU passthrough opt)

let
  cfg = config.solem.virtualization;
in {
  options.solem.virtualization = {
    enable = lib.mkEnableOption "Virtualizzazione completa (KVM + libvirt + Distrobox)";

    distrobox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Distrobox: gira altre distro come container persistenti";
    };

    virtManagerGui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "virt-manager GUI";
    };

    lookingGlass = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Looking Glass (VFIO GPU passthrough, advanced)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── libvirtd + KVM ──
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;        # TPM virtuale (per Win11 VM)
        ovmf = {
          enable = true;
          packages = [ (pkgs.OVMFFull.override {
            secureBoot = true;
            tpmSupport = true;
          }).fd ];
        };
      };
    };

    # User gavio nei gruppi virtualization
    users.users.gavio.extraGroups = lib.mkAfter [ "libvirtd" "kvm" ];

    # Networking VM (default bridge virbr0)
    virtualisation.libvirtd.allowedBridges = [ "virbr0" "br0" ];

    # ── Container runtime (Distrobox + Podman) ──
    virtualisation.podman = lib.mkIf cfg.distrobox {
      enable = true;
      dockerCompat = false;       # convivenza con docker se installato
      defaultNetwork.settings.dns_enabled = true;
    };

    environment.systemPackages = with pkgs; [
      qemu_kvm
      virtiofsd                    # condividi cartelle host↔guest
      spice-gtk                    # display VM hot-plug
      libosinfo                    # info distro per virt-install
      cloud-utils                  # genera ISO cloud-init
    ] ++ lib.optionals cfg.virtManagerGui [
      virt-manager
      virt-viewer
      gnome-boxes                  # alternativa friendly per principianti
    ] ++ lib.optionals cfg.distrobox [
      distrobox
      podman-compose
      podman-tui
      toolbox
    ] ++ lib.optionals cfg.lookingGlass [
      looking-glass-client
    ];

    # ── SPICE clipboard sharing host↔guest ──
    services.spice-vdagentd.enable = true;
    services.spice-webdavd.enable = true;

    # ── Banner ──
    environment.etc."solem/virtualization.md".text = ''
      # SOLEM Virtualization

      ## VM con virt-manager GUI
      virt-manager → Create new VM → seleziona ISO

      ## Distrobox (altre distro senza VM)
      distrobox create -n ubuntu24 -i quay.io/toolbx-images/ubuntu-toolbox:24.04
      distrobox enter ubuntu24
      apt install whatever

      Hai una shell Ubuntu pulita ma con accesso a /home, audio, GPU.
      No overhead di una VM intera.

      ## Toolbox (Fedora-style)
      toolbox create
      toolbox enter

      ## Cluster integration
      Le VM/container sono visibili a solem-cluster come sub-device:
      esempio: VM Windows 11 con GPU passthrough → workstation +1
    '';
  };
}
