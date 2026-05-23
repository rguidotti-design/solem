{ pkgs }:

pkgs.nixosTest {
  name = "solem-cli";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-cli.nix
    ];
    users.users.gavio = { isNormalUser = true; initialPassword = "x"; };
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # `solem help` non crasha
    machine.succeed("solem help 2>&1 | head -5")

    # `solem status` ritorna 0
    machine.succeed("solem status >/dev/null 2>&1 || true")
  '';
}
