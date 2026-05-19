{ config, pkgs, lib, ... }:

let
  cfg = config.solem.profile;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM PROFILES — preset dichiarativi
  # ──────────────────────────────────────────────────────────────────────
  # Invece di abilitare 20 opzioni a mano, scegli un PROFILE e SOLEM
  # configura coerentemente sicurezza/desktop/dev/AI/networking.
  #
  # Profili disponibili:
  #
  #   minimal     — solo core SOLEM + GAVIO. No desktop, no dev tools.
  #                 Target: VM test, edge node, IoT bridge.
  #
  #   developer   — minimal + dev tools (Python/Node/Go/Rust) + container.
  #                 Target: laptop / workstation di chi sviluppa con AI.
  #
  #   creator     — developer + ai (Jupyter, ML libs) + creative tools.
  #                 Target: artist/researcher che usa AI per creare.
  #
  #   server      — minimal + hardening max + mesh attiva + zero-trust.
  #                 Target: Beelink/datacenter, sempre acceso, multi-device.
  #
  #   desktop     — developer + desktop GUI (Hyprland) + browser + media.
  #                 Target: PC primario quotidiano.
  #
  # Combinabili manualmente: solem.creator.ai.enable = true; sopra qualunque profilo.

  options.solem.profile = lib.mkOption {
    type = lib.types.enum [ "minimal" "developer" "creator" "server" "desktop" ];
    default = "minimal";
    description = "Profilo SOLEM dichiarativo. Configura coerentemente tutti i moduli.";
    example = "creator";
  };

  config = lib.mkMerge [
    # ── DEVELOPER ────────────────────────────────────────────────────
    (lib.mkIf (cfg == "developer") {
      solem.creator.dev = {
        enable = lib.mkDefault true;
        languages = lib.mkDefault [ "python" "node" "go" "rust" ];
      };
      virtualisation.docker.enable = lib.mkDefault true;
    })

    # ── CREATOR ──────────────────────────────────────────────────────
    (lib.mkIf (cfg == "creator") {
      solem.creator.dev.enable = lib.mkDefault true;
      solem.creator.ai.enable = lib.mkDefault true;
      solem.creator.data = lib.mkDefault true;
      solem.creator.creative = lib.mkDefault true;
      virtualisation.docker.enable = lib.mkDefault true;
    })

    # ── SERVER ───────────────────────────────────────────────────────
    (lib.mkIf (cfg == "server") {
      solem.secure.kernelHardening.enable = lib.mkDefault true;
      solem.mesh.enable = lib.mkDefault true;
      solem.zeroTrust.enable = lib.mkDefault true;
      # Niente desktop
      solem.desktop.enable = lib.mkDefault false;
      # No browser, no media — solo headless services
      services.openssh.settings.PasswordAuthentication = lib.mkDefault false;  # solo key
    })

    # ── DESKTOP ──────────────────────────────────────────────────────
    (lib.mkIf (cfg == "desktop") {
      solem.creator.dev.enable = lib.mkDefault true;
      solem.desktop.enable = lib.mkDefault true;
      solem.secure.kernelHardening.enable = lib.mkDefault true;
    })

    # ── MINIMAL (default) ────────────────────────────────────────────
    # Nessun override — i moduli restano ai loro default.
    # Output: SOLEM core + GAVIO + dashboard + boot premium. Niente di più.

    # Etichetta profilo nel manifest SOLEM (visibile in /solem/manifest)
    {
      environment.etc."solem/profile".text = cfg;
    }
  ];
}
