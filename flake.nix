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
      # ────────────────────────────────────────────────────────────────
      nixosConfigurations = {

        # VM x86_64 MINIMAL — `nix run .#vm` (CI-friendly, build veloce)
        solem-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration-vm-minimal.nix
            ./nixos/hardware-vm.nix
          ];
        };

        # VM x86_64 FULL — config completa (può rompersi)
        solem-vm-full = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration.nix
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

        # Raspberry Pi 4/5 — `nix build .#raspberry`
        solem-raspberry = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
            nixos-hardware.nixosModules.raspberry-pi-4
            ./nixos/configuration-edge.nix
            ./nixos/modules/solem-edge.nix
            ./nixos/modules/solem-raspberry.nix
            ({ ... }: { solem.edge.enable = true; solem.raspberry.enable = true; })
          ];
        };

        # Jetson Nano/Orin — `nix build .#jetson`
        solem-jetson = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
            ./nixos/configuration-edge.nix
            ./nixos/modules/solem-edge.nix
            ./nixos/modules/solem-jetson.nix
            ({ ... }: { solem.edge.enable = true; solem.jetson.enable = true; })
          ];
        };
      };

      # ────────────────────────────────────────────────────────────────
      # Pacchetti per ogni arch
      # ────────────────────────────────────────────────────────────────
      packages = forAllSystems (system: let
        cfgs = self.nixosConfigurations;
      in (if system == "x86_64-linux" then {
        default = cfgs.solem-vm.config.system.build.vm;
        vm      = cfgs.solem-vm.config.system.build.vm;
        iso     = cfgs.solem-iso.config.system.build.isoImage;
      } else {
        default   = cfgs.solem-raspberry.config.system.build.sdImage;
        raspberry = cfgs.solem-raspberry.config.system.build.sdImage;
        jetson    = cfgs.solem-jetson.config.system.build.sdImage;
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
