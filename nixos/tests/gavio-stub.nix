{ pkgs }:

# Verifica GAVIO stub: builda il package + invoca --help
pkgs.nixosTest {
  name = "solem-gavio-stub";

  nodes.machine = { config, pkgs, lib, ... }:
  let
    gavio = pkgs.callPackage ../../nix/gavio.nix {};
  in {
    imports = [ ../modules/solem-core.nix ];
    environment.systemPackages = [ gavio ];
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # CLI presente
    machine.succeed("which gavio-server")

    # Lancia in background su porta 8765 (no clash)
    machine.succeed("GAVIO_PORT=8765 GAVIO_HOST=127.0.0.1 gavio-server &")
    machine.sleep(2)

    # Verifica health endpoint
    out = machine.succeed("curl -fsS http://127.0.0.1:8765/health")
    assert '"status"' in out and '"stub"' in out, f"GAVIO stub health failed: {out}"

    # Verifica /v2/capabilities
    out = machine.succeed("curl -fsS http://127.0.0.1:8765/v2/capabilities")
    assert "capabilities" in out, f"capabilities endpoint failed: {out}"

    # Verifica POST /v2/agent/query
    out = machine.succeed(
      "curl -fsS -X POST -H 'Content-Type: application/json' "
      "-d '{\"query\":\"test\"}' http://127.0.0.1:8765/v2/agent/query"
    )
    assert "response" in out and "stub" in out, f"agent query failed: {out}"
  '';
}
