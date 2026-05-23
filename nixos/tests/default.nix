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

  # Test 3 — Spotlight CLI (anyrun + plugin GAVIO) presente
  spotlight = import ./spotlight.nix { inherit pkgs; };

  # Test 4 — Quick Settings toggles (wifi/bt/vpn/focus) eseguibili
  quick-settings = import ./quick-settings.nix { inherit pkgs; };

  # Test 5 — GAVIO context: tutti i tool (wl-clipboard, grim, slurp, tesseract) installati
  gavio-context = import ./gavio-context.nix { inherit pkgs; };

  # Test 6 — Italian locale (it_IT.UTF-8 + hunspell-it disponibili)
  italian-locale = import ./italian-locale.nix { inherit pkgs; };

  # Test 7 — Backup CLI (`solem-priv`, `solem-clean`, `solem-media`)
  user-clis = import ./user-clis.nix { inherit pkgs; };

  # Test 8 — Mesh interface (wg-solem) creata
  mesh-iface = import ./mesh-iface.nix { inherit pkgs; };
}
