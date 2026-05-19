{
  description = "SOLEM — OS AI-native che ospita GAVIO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      nixosConfigurations = {
        # Variante VM: testabile via `nix run .#vm` senza intaccare l'host.
        # Monta GAVIO da host via 9p shared folder.
        solem-vm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/configuration.nix
            ./nixos/hardware-vm.nix
          ];
        };

        # Variante bare-metal (Beelink Step 1): da estendere quando arriva l'hw.
        # solem-bare = nixpkgs.lib.nixosSystem { ... };
      };

      # Eseguibile pronto-all-uso: `nix run .#vm` lancia QEMU con SOLEM.
      packages.${system}.vm =
        self.nixosConfigurations.solem-vm.config.system.build.vm;

      # Shell di sviluppo: `nix develop` per avere nixos-rebuild + tool a portata.
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixos-rebuild
          qemu
          git
        ];
      };
    };
}
