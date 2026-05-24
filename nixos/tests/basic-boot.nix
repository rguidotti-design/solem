{ pkgs }:

pkgs.nixosTest {
  name = "solem-basic-boot";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-cli.nix
      ../modules/solem-motd.nix
    ];

    # solem-core dichiara già users.users.gavio. NON ridichiarare.

    networking.hostName = "solem-test";
    time.timeZone = "Europe/Rome";
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Utente esiste
    machine.succeed("id gavio")

    # MOTD presente
    machine.succeed("test -e /etc/motd || test -e /run/motd.dynamic.d")

    # `solem` CLI presente
    machine.succeed("which solem")

    # hostname corretto
    out = machine.succeed("hostname")
    assert "solem-test" in out, f"hostname mismatch: {out}"
  '';
}
