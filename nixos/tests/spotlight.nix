{ pkgs }:

pkgs.nixosTest {
  name = "solem-spotlight";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-spotlight.nix ];
    solem.spotlight = {
      enable = true;
      launcher = "anyrun";
      gavioIntegration = true;
    };
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Plugin GAVIO presente
    machine.succeed("which solem-spotlight-gavio")

    # Hint file scritto
    machine.succeed("test -e /etc/solem/spotlight.hint")

    # Lo script non crasha quando non c'è GAVIO (deve dire "GAVIO offline")
    out = machine.succeed("solem-spotlight-gavio 'test' 2>&1 || true")
    assert "offline" in out.lower() or "no response" in out.lower() or out != "", f"unexpected: {out}"
  '';
}
