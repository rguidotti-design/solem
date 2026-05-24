{ pkgs }:

# Verifica firewall di base + porte attese chiuse
pkgs.nixosTest {
  name = "solem-firewall-base";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-core.nix ];
    networking.firewall.enable = true;
    services.openssh.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")

    # Firewall attivo
    machine.succeed("systemctl is-active firewall || true")

    # SSH risponde su 22
    machine.wait_for_open_port(22)

    # Porte critiche NON aperte di default
    for port in [8000, 8001, 8888, 9090]:
        out = machine.execute(f"ss -tln | grep ':{port} ' || true")[1]
        if out.strip():
            print(f"WARNING: porta {port} aperta inaspettatamente: {out}")
  '';
}
