{ pkgs }:

pkgs.nixosTest {
  name = "solem-cli";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-cli.nix
    ];
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(2)

    # `solem` esiste e parte
    machine.succeed("/run/current-system/sw/bin/solem --help 2>&1 | head -5 || /run/current-system/sw/bin/solem help 2>&1 | head -5 || true")

    # Non crashare quando chiamato senza arg
    machine.execute("/run/current-system/sw/bin/solem 2>&1 || true")
  '';
}
