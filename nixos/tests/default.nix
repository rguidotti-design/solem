# SOLEM — NixOS VM tests (`nix flake check` esegue questi).
#
# Single responsibility: SOLO registro dei test. Ogni test è in un file.
# Tutti i test girano in QEMU/KVM senza richiedere hardware reale → 0 €.
{ pkgs, nixosConfigurations }:

{
  # Test 1 — la VM SOLEM boota e ha utente "gavio"
  basic-boot = import ./basic-boot.nix { inherit pkgs; };

  # Test 2 — `solem` CLI risponde a status / help
  solem-cli = import ./solem-cli.nix { inherit pkgs; };

  # Test 5 — Firewall base + SSH funzionante (Test 3/4 temp rimossi)
  firewall-base = import ./firewall-base.nix { inherit pkgs; };

  # ── Temp disabilitati per debug Quick Validate:
  # solem-demo = import ./solem-demo.nix { inherit pkgs; };
  # gavio-stub = import ./gavio-stub.nix { inherit pkgs; };

  # ── Disabilitati per ora (richiedono moduli con pkg dubbi):
  # spotlight = import ./spotlight.nix { inherit pkgs; };
  # quick-settings = import ./quick-settings.nix { inherit pkgs; };
  # gavio-context = import ./gavio-context.nix { inherit pkgs; };
  # italian-locale = import ./italian-locale.nix { inherit pkgs; };
  # user-clis = import ./user-clis.nix { inherit pkgs; };
  # mesh-iface = import ./mesh-iface.nix { inherit pkgs; };
}
