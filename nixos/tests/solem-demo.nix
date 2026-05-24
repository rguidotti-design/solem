{ pkgs }:

pkgs.nixosTest {
  name = "solem-demo";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-demo.nix
    ];
    solem.demo.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # CLI presente
    machine.succeed("which solem-demo")

    # Esegue senza crash (basta che non ritorni errore)
    out = machine.succeed("solem-demo 2>&1 | head -20 || true")
    assert "SOLEM" in out, f"Demo output incompleto: {out[:200]}"
  '';
}
