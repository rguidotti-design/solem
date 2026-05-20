{ config, pkgs, lib, ... }:

# SOLEM CONTAINERS — runtime container e orchestration, opt-in.
#
# Single responsibility: SOLO orchestrare runtime (Podman rootless / Docker
# rootless / k3s). Niente immagini preinstallate.
#
# Default: Podman rootless (più sicuro di Docker, no daemon root).
# K3s opzionale per chi vuole kubernetes locale.
#
# 100% FOSS, 0 €.

let
  cfg = config.solem.containers;
in {
  options.solem.containers = {
    podman = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Podman rootless (alternativa sicura a Docker)";
    };

    docker = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Docker (rootful daemon)";
    };

    dockerRootless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Docker rootless (più sicuro)";
    };

    k3s = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "K3s lightweight Kubernetes (single-node)";
    };

    distrobox = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Distrobox (esegui altre distro come container persistenti)";
    };
  };

  config = lib.mkMerge [
    # Podman rootless
    (lib.mkIf cfg.podman {
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;  # alias docker → podman
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };
      environment.systemPackages = with pkgs; [
        podman-compose podman-tui
      ];
    })

    # Docker daemon (rootful)
    (lib.mkIf cfg.docker {
      virtualisation.docker = {
        enable = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
        rootless = lib.mkIf cfg.dockerRootless {
          enable = true;
          setSocketVariable = true;
        };
      };
      users.users.gavio.extraGroups = lib.mkIf (!cfg.dockerRootless) [ "docker" ];
    })

    # K3s
    (lib.mkIf cfg.k3s {
      services.k3s = {
        enable = true;
        role = "server";
        extraFlags = "--write-kubeconfig-mode 644";
      };
      environment.systemPackages = with pkgs; [
        kubectl k9s helm
      ];
      networking.firewall.allowedTCPPorts = [ 6443 ];
    })

    # Distrobox (richiede podman o docker)
    (lib.mkIf cfg.distrobox {
      environment.systemPackages = with pkgs; [ distrobox boxbuddy ];
    })
  ];
}
