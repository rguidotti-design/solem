{
  description = "SOLEM — OS AI-native multi-arch (x86_64 + aarch64) che ospita GAVIO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-hardware }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {

      # ────────────────────────────────────────────────────────────────
      # NixOS configurations
      # NOTA: temporaneamente ridotte al minimo CI-friendly.
      # solem-vm-full, raspberry, jetson sono COMMENTATI finché
      # non passano singolarmente l'eval. Ricostruzione incrementale.
      # ────────────────────────────────────────────────────────────────
      nixosConfigurations = {

        # VM x86_64 MINIMAL — `nix run .#vm`
        solem-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration-vm-minimal.nix
            ./nixos/hardware-vm.nix
          ];
        };

        # VM DESKTOP x86_64 — `nix build .#vm-desktop` (Hyprland Wayland)
        solem-vm-desktop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration-vm-desktop.nix
            ./nixos/hardware-vm.nix
          ];
        };

        # ISO live x86_64 — `nix build .#iso`
        solem-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
            ./nixos/configuration-vm-minimal.nix
            ./nixos/iso-overlay.nix
          ];
        };

        # ── Disabilitati per ora (vedere docs/OPERATIVE.md) ────────────
        # solem-vm-full: 130+ moduli, eval rompe per nomi/opzioni
        # solem-raspberry: importa configuration-edge.nix + solem-api/cluster
        # solem-jetson: idem
      };

      # ────────────────────────────────────────────────────────────────
      # Pacchetti per ogni arch
      # ────────────────────────────────────────────────────────────────
      packages = forAllSystems (system: let
        cfgs = self.nixosConfigurations;
      in (if system == "x86_64-linux" then {
        default    = cfgs.solem-vm.config.system.build.vm;
        vm         = cfgs.solem-vm.config.system.build.vm;
        vm-desktop = cfgs.solem-vm-desktop.config.system.build.vm;
        iso        = cfgs.solem-iso.config.system.build.isoImage;
      } else {
        # aarch64-linux: nessun package finché raspberry/jetson eval-clean
      }));

      # ────────────────────────────────────────────────────────────────
      # `nix flake check` — VM tests
      # ────────────────────────────────────────────────────────────────
      checks = forAllSystems (system:
        if system == "x86_64-linux" then
          import ./nixos/tests { pkgs = pkgsFor system; nixosConfigurations = self.nixosConfigurations; }
        else {}
      );

      # ────────────────────────────────────────────────────────────────
      # Dev shells
      # ────────────────────────────────────────────────────────────────
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          buildInputs = with (pkgsFor system); [
            nixos-rebuild
            qemu
            git
            nixpkgs-fmt
            statix
            deadnix
          ];
          shellHook = ''
            echo "── SOLEM dev shell ──"
            echo "  nix run .#vm                 → boot VM SOLEM"
            echo "  nix build .#iso              → build ISO live"
            echo "  nix flake check              → esegui VM tests"
          '';
        };
      });

      # ────────────────────────────────────────────────────────────────
      # Formatter per `nix fmt`
      # ────────────────────────────────────────────────────────────────
      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
