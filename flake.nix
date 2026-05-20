{
  description = "SOLEM — OS AI-native multi-arch (x86_64 + aarch64) che ospita GAVIO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-hardware }:
    let
      # Supportiamo workstation x86_64 + edge ARM64 (Raspberry/Jetson)
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      nixosConfigurations = {

        # ─── x86_64 ─────────────────────────────────────────────────

        # VM x86_64: testabile via `nix run .#vm` senza intaccare l'host.
        solem-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./nixos/configuration.nix
            ./nixos/hardware-vm.nix
          ];
        };

        # ISO bootable x86_64: `nix build .#iso`
        solem-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
            ./nixos/configuration.nix
            ({ config, pkgs, lib, ... }: {
              # ISO mode: disabilita servizi che richiedono /etc/solem persistente
              systemd.services.gavio.enable = lib.mkForce false;
              services.xserver.enable = lib.mkForce false;
              services.getty.greetingLine = ''
                ╔════════════════════════════════════════════════════╗
                ║  SOLEM — AI-native OS · live ISO (x86_64)         ║
                ║  user: gavio · pass: gavio                        ║
                ║  Per installare: vedi INSTALL.md sul repo         ║
                ╚════════════════════════════════════════════════════╝
              '';
              users.users.gavio.initialPassword = lib.mkForce "gavio";
              networking.wireless.enable = lib.mkForce false;
              networking.networkmanager.enable = lib.mkForce true;
            })
          ];
        };

        # ─── aarch64 (ARM) ──────────────────────────────────────────

        # Raspberry Pi 4/5 — SD card image: `nix build .#raspberry`
        solem-raspberry = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
            nixos-hardware.nixosModules.raspberry-pi-4
            ./nixos/configuration-edge.nix
            ./nixos/modules/solem-edge.nix
            ./nixos/modules/solem-raspberry.nix
            ({ config, pkgs, lib, ... }: {
              solem.edge.enable = true;
              solem.raspberry.enable = true;
            })
          ];
        };

        # Jetson Nano/Orin — SD image con Tegra: `nix build .#jetson`
        solem-jetson = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            (nixpkgs + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
            ./nixos/configuration-edge.nix
            ./nixos/modules/solem-edge.nix
            ./nixos/modules/solem-jetson.nix
            ({ config, pkgs, lib, ... }: {
              solem.edge.enable = true;
              solem.jetson.enable = true;
            })
          ];
        };
      };

      # ─── Pacchetti per ogni target ──
      packages = forAllSystems (system: let
        cfgs = self.nixosConfigurations;
        # Sui x86_64 buildiamo vm + iso, sugli aarch64 buildiamo sd-image
      in (if system == "x86_64-linux" then {
        default = cfgs.solem-vm.config.system.build.vm;
        vm      = cfgs.solem-vm.config.system.build.vm;
        iso     = cfgs.solem-iso.config.system.build.isoImage;
      } else {
        default   = cfgs.solem-raspberry.config.system.build.sdImage;
        raspberry = cfgs.solem-raspberry.config.system.build.sdImage;
        jetson    = cfgs.solem-jetson.config.system.build.sdImage;
      }));

      # ─── Shell di sviluppo per ogni arch ──
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          buildInputs = with (pkgsFor system); [
            nixos-rebuild
            qemu
            git
          ];
        };
      });
    };
}
