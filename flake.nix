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

        # Variante ISO bootable: `nix build .#iso` produce un'immagine
        # installabile su PC vero (USB stick → boot).
        solem-iso = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
            ./nixos/configuration.nix
            ({ config, pkgs, lib, ... }: {
              # In ISO mode: niente moduli che richiedono /etc/solem persistente
              services.gavio.enable = lib.mkForce false;
              # ISO leggera: niente desktop pesante (cage/Hyprland) di default
              services.xserver.enable = lib.mkForce false;
              # Banner di benvenuto
              services.getty.greetingLine = ''
                ╔════════════════════════════════════════════════════╗
                ║  SOLEM — AI-native OS · live ISO                  ║
                ║  user: gavio · pass: gavio                        ║
                ║  Per installare: sudo nixos-install ...           ║
                ║  Doc: https://github.com/rguidotti-design/solem   ║
                ╚════════════════════════════════════════════════════╝
              '';
              # Install rooted user con password gavio (live mode only)
              users.users.gavio.initialPassword = lib.mkForce "gavio";
              networking.wireless.enable = lib.mkForce false;
              networking.networkmanager.enable = lib.mkForce true;
            })
          ];
        };

        # Variante bare-metal (Beelink Step 1): da estendere quando arriva l'hw.
        # solem-bare = nixpkgs.lib.nixosSystem { ... };
      };

      # Eseguibile pronto-all-uso: `nix run .#vm` lancia QEMU con SOLEM.
      packages.${system} = {
        vm  = self.nixosConfigurations.solem-vm.config.system.build.vm;
        iso = self.nixosConfigurations.solem-iso.config.system.build.isoImage;
      };

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
