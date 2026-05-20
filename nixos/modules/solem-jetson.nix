{ config, pkgs, lib, ... }:

# SOLEM JETSON NANO/ORIN — NVIDIA Tegra ARM64 con CUDA.
#
# Single responsibility: SOLO config Jetson-specific:
#   - L4T BSP NVIDIA (kernel + drivers Tegra)
#   - CUDA runtime + Tegra GPU passthrough
#   - Ollama GPU enabled (modelli 7B-13B su Orin, 1B-7B su Nano)
#   - llama.cpp con CUDA
#
# NB: la Jetson richiede L4T NVIDIA, non kernel mainline. NixOS supporto
# è parziale (jetson-nano-2gb-developer kit). Step 1+: integrare
# jetpack-nixos overlay per BSP completo.
#
# Per ora: scaffold + flag CUDA. L'utente deve fornire device tree.

let
  cfg = config.solem.jetson;
in {
  options.solem.jetson = {
    enable = lib.mkEnableOption "Jetson Nano/Orin con CUDA Tegra";

    model = lib.mkOption {
      type = lib.types.enum [ "nano" "nano-2gb" "xavier-nx" "orin-nano" "orin-nx" ];
      default = "orin-nano";
      description = "Modello Jetson";
    };

    enableCuda = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Abilita CUDA per Ollama/llama.cpp inference su GPU Tegra";
    };

    enableOllamaGpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configura Ollama per usare la GPU Jetson";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── NVIDIA Tegra: richiede overlay jetpack-nixos (Step 1+) ───
    # Per ora: marker + env, l'utente deve aggiungere il BSP manualmente.
    nixpkgs.config.allowUnfree = true;

    # ─── CUDA toolkit + runtime ───
    environment.systemPackages = with pkgs; lib.optionals cfg.enableCuda [
      # NB: cudatoolkit su aarch64 richiede jetpack-nixos. Scaffold:
      # cudatoolkit  # commentato finché jetpack-nixos non è integrato
      nvtopPackages.full
    ] ++ [
      v4l-utils      # video for linux (camera Jetson)
      ffmpeg-full    # encoding hw NVENC se BSP lo espone
    ];

    # ─── Ollama GPU ───
    services.ollama = lib.mkIf cfg.enableOllamaGpu {
      acceleration = "cuda";  # richiede CUDA libs nel PATH
    };

    # ─── Edge device class ───
    solem.edge.deviceClass = lib.mkDefault "edge-gpu";

    # ─── Hostname ───
    networking.hostName = lib.mkDefault "solem-jetson-${cfg.model}";

    # ─── Banner che spiega lo stato ───
    environment.etc."solem/jetson-info.md".text = ''
      # SOLEM Jetson — ${cfg.model}

      Questo profilo richiede l'overlay **jetpack-nixos** per il BSP NVIDIA
      completo (L4T kernel, CUDA Tegra, NVENC hw encoding).

      Step di completamento (manuale):
        1. Aggiungi `jetpack-nixos.url = "github:anduril/jetpack-nixos";`
           agli inputs di flake.nix
        2. Importa `jetpack-nixos.nixosModules.default`
        3. Imposta `hardware.nvidia-jetpack.enable = true;`

      Vedi: https://github.com/anduril/jetpack-nixos
    '';
  };
}
