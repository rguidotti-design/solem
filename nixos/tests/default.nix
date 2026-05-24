# SOLEM — NixOS VM tests (`nix flake check` esegue questi).
#
# Single responsibility: SOLO registro dei test. Ogni test è in un file.
# Tutti i test girano in QEMU/KVM senza richiedere hardware reale → 0 €.
#
# TEMPORANEAMENTE solo basic-boot + solem-cli mentre stabilizziamo CI.
# Gli altri 6 test sono in nixos/tests/ ma esclusi dai checks finché
# non verifichiamo che ogni modulo importato non rompe l'eval.
{ pkgs, nixosConfigurations }:

{
  # Test 1 — la VM SOLEM boota e ha utente "gavio"
  basic-boot = import ./basic-boot.nix { inherit pkgs; };

  # Test 2 — `solem` CLI risponde a status / help
  solem-cli = import ./solem-cli.nix { inherit pkgs; };

  # ── Disabilitati per ora (vedere docs/OPERATIVE.md) ────────────────
  # spotlight = import ./spotlight.nix { inherit pkgs; };
  # quick-settings = import ./quick-settings.nix { inherit pkgs; };
  # gavio-context = import ./gavio-context.nix { inherit pkgs; };
  # italian-locale = import ./italian-locale.nix { inherit pkgs; };
  # user-clis = import ./user-clis.nix { inherit pkgs; };
  # mesh-iface = import ./mesh-iface.nix { inherit pkgs; };
}
