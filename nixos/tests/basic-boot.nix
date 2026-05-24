{ pkgs }:

pkgs.nixosTest {
  name = "solem-basic-boot";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-cli.nix
      ../modules/solem-motd.nix
    ];

    networking.hostName = "solem-test";
    time.timeZone = "Europe/Rome";
    system.stateVersion = "24.11";
  };

  testScript = ''
    # Aspetta system pronto (max 60s)
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(2)

    # Utente gavio esiste (da solem-core)
    machine.succeed("id gavio || getent passwd gavio")

    # solem CLI presente nel PATH (writePython3Bin)
    machine.succeed("ls /run/current-system/sw/bin/solem || which solem")

    # hostname configurato
    out = machine.succeed("hostname")
    assert "solem-test" in out, f"hostname mismatch: {out!r}"

    # Diagnostica utile (no fail anche se manca)
    machine.execute("cat /etc/os-release || true")
    machine.execute("systemctl list-units --type=service --state=failed --no-pager || true")
  '';
}
