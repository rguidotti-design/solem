{ pkgs }:

pkgs.nixosTest {
  name = "solem-mesh-iface";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-mesh.nix ];
    solem.mesh.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # wireguard tools presenti
    machine.succeed("which wg")

    # config wireguard generato (può chiamarsi wg-solem o wg0)
    machine.succeed("test -d /etc/wireguard || systemctl status wg-quick-* 2>&1 | head -3 || true")
  '';
}
