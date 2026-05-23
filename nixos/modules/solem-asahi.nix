{ config, pkgs, lib, ... }:

# SOLEM ASAHI — SOLEM su Apple Silicon Mac (M1/M2/M3/M4) via asahi-linux.
#
# Single responsibility: SOLO scaffold per integrare il kernel + drivers
# asahi-linux. Il vero supporto richiede:
#   1. Apple Silicon Mac in dual boot (asahi installer prima)
#   2. Aggiungere `asahi-nix` flake input
#   3. Includere `asahi-nix.nixosModules.default` qui
#
# Asahi è community-driven: GPU progresso ottimo, audio/sleep parziali.
# Considerare opt-in solo se l'utente sa cosa fa.

let
  cfg = config.solem.asahi;
in {
  options.solem.asahi = {
    enable = lib.mkEnableOption "SOLEM su Apple Silicon (asahi-linux scaffold)";

    model = lib.mkOption {
      type = lib.types.enum [ "m1" "m1-pro" "m1-max" "m1-ultra"
                              "m2" "m2-pro" "m2-max" "m2-ultra"
                              "m3" "m3-pro" "m3-max"
                              "m4" "m4-pro" "m4-max" ];
      default = "m1";
      description = "Modello SoC Apple";
    };

    enableGpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "GPU Apple (asahi-mesa). Stabile su M1, alpha su M3+";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── ARM64 ──
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # ── Banner istruzioni (in attesa integrazione asahi-nix overlay) ──
    environment.etc."solem/asahi-setup.md".text = ''
      # SOLEM su Apple Silicon (${cfg.model})

      Questo profilo è uno **scaffold**. Per uso reale:

      1. Installa prima asahi-linux da macOS:
         `curl https://alx.sh | sh`

      2. Aggiungi al flake.nix input:
         ```nix
         inputs.asahi-nix.url = "github:tpwrules/nixos-apple-silicon";
         ```

      3. Importa il modulo:
         ```nix
         modules = [
           asahi-nix.nixosModules.default
           {
             hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
             hardware.asahi.useExperimentalGPUDriver = ${if cfg.enableGpu then "true" else "false"};
           }
         ];
         ```

      4. nix build .#asahi-${cfg.model}
      5. Flash via asahi installer e boot in NixOS

      ## Cosa funziona oggi (asahi 0.8+)
      - ✅ CPU full speed
      - ✅ GPU rendering (gnome, kde, firefox WebGL)
      - ✅ WiFi, Bluetooth, audio
      - ✅ Touchpad, keyboard, touchbar
      - 🟡 Display brightness, sleep, fan control
      - ❌ HDMI/DisplayPort output, Thunderbolt, microfono interno

      Vedi: https://asahilinux.org/
    '';

    # ── Edge class ──
    solem.edge.deviceClass = lib.mkDefault "workstation";

    networking.hostName = lib.mkDefault "solem-mac-${cfg.model}";
  };
}
