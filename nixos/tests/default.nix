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

  # Test 5 — Firewall base + SSH funzionante
  firewall-base = import ./firewall-base.nix { inherit pkgs; };

  # Test 6 — solem-demo CLI (semplificato, solo echo no gum)
  solem-demo = import ./solem-demo.nix { inherit pkgs; };

  # Test 7 — AI guardrails sandbox (test/exec/audit log)
  ai-guardrails = import ./ai-guardrails.nix { inherit pkgs; };

  # Test 8 — gavio-ai user isolation REALE (file access + sudo + groups)
  ai-user-isolation = import ./ai-user-isolation.nix { inherit pkgs; };

  # Test 9 — nftables egress whitelist (BLOCK reale, non solo log)
  ai-network-egress = import ./ai-network-egress.nix { inherit pkgs; };

  # Test 10 — GAVIO zero-trust: override systemd User/caps/syscall
  gavio-zero-trust = import ./gavio-zero-trust.nix { inherit pkgs; };

  # Test 11 — Canary trip + kill switch (read honey token -> gavio stop)
  canary-trip = import ./canary-trip.nix { inherit pkgs; };

  # Test 12 — RED-TEAM: 8 attacchi reali da gavio-ai, tutti DEVONO fallire
  red-team-ai = import ./red-team-ai.nix { inherit pkgs; };

  # Test 13 — Kernel hardening sysctl + lockdown + module blacklist
  kernel-harden = import ./kernel-harden.nix { inherit pkgs; };

  # Test 14 — DNS allowlist + NAT redirect per gavio-ai (anti tunneling)
  ai-dns-allowlist = import ./ai-dns-allowlist.nix { inherit pkgs; };

  # ── Temp disabilitato (richiede build package gavio):
  # gavio-stub = import ./gavio-stub.nix { inherit pkgs; };

  # ── Disabilitati per ora (richiedono moduli con pkg dubbi):
  # spotlight = import ./spotlight.nix { inherit pkgs; };
  # quick-settings = import ./quick-settings.nix { inherit pkgs; };
  # gavio-context = import ./gavio-context.nix { inherit pkgs; };
  # italian-locale = import ./italian-locale.nix { inherit pkgs; };
  # user-clis = import ./user-clis.nix { inherit pkgs; };
  # mesh-iface = import ./mesh-iface.nix { inherit pkgs; };
}
