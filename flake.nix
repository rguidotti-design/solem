{
  description = "SOLEM — OS AI-native multi-arch (x86_64 + aarch64) che ospita GAVIO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Home Manager 24.11 (utente-side config, FOSS)
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Pacchetto GAVIO (backend Python come Nix derivation, opzionale)
      gavioPkg = system: (pkgsFor system).callPackage ./nix/gavio.nix {};

      # Tutti i moduli home-manager di SOLEM (auto-symlink config user)
      homeModules = import ./home/modules;
    in {

      # ────────────────────────────────────────────────────────────────
      # NixOS configurations (host system)
      # ────────────────────────────────────────────────────────────────
      nixosConfigurations = {

        # VM x86_64 — `nix run .#vm`
        solem-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration.nix
            ./nixos/hardware-vm.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # Default home config (solo se l'utente "gavio" esiste)
              home-manager.users.gavio = { ... }: {
                imports = builtins.attrValues homeModules;
                home.stateVersion = "24.11";
              };
            }
          ];
        };

        # ISO live x86_64 — `nix build .#iso`
        solem-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
            ./nixos/configuration.nix
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
      # Standalone home-manager configurations
      # Per chi gira NixOS non-SOLEM ma vuole solo i nostri home modules.
      # ────────────────────────────────────────────────────────────────
      homeConfigurations = forAllSystems (system: {
        default = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = builtins.attrValues homeModules ++ [
            { home.username = "gavio"; home.homeDirectory = "/home/gavio"; home.stateVersion = "24.11"; }
          ];
        };
      });

      # ────────────────────────────────────────────────────────────────
      # Pacchetti per ogni arch
      # ────────────────────────────────────────────────────────────────
      packages = forAllSystems (system: let
        cfgs = self.nixosConfigurations;
        commonPkgs = {
          gavio = gavioPkg system;
        };
      in commonPkgs // (if system == "x86_64-linux" then {
        default = cfgs.solem-vm.config.system.build.vm;
        vm      = cfgs.solem-vm.config.system.build.vm;
        iso     = cfgs.solem-iso.config.system.build.isoImage;
      } else {
        default   = cfgs.solem-raspberry.config.system.build.sdImage;
        raspberry = cfgs.solem-raspberry.config.system.build.sdImage;
        jetson    = cfgs.solem-jetson.config.system.build.sdImage;
      }));

      # ────────────────────────────────────────────────────────────────
      # `nix flake check` — chiama gli NixOS VM tests
      # ────────────────────────────────────────────────────────────────
      checks = forAllSystems (system:
        if system == "x86_64-linux" then
          import ./nixos/tests { pkgs = pkgsFor system; inherit (self) nixosConfigurations; }
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
            home-manager.packages.${system}.home-manager
          ];
          shellHook = ''
            echo "── SOLEM dev shell ──"
            echo "Comandi utili:"
            echo "  nix run .#vm                 → boot VM SOLEM"
            echo "  nix build .#iso              → build ISO live"
            echo "  nix flake check              → esegui VM tests"
            echo "  nix build .#gavio            → impacchetta backend GAVIO"
            echo "  statix check && deadnix .    → lint Nix"
          '';
        };
      });

      # ────────────────────────────────────────────────────────────────
      # Formatter per `nix fmt`
      # ────────────────────────────────────────────────────────────────
      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
