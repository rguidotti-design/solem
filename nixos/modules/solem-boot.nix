{ config, pkgs, lib, ... }:

let
  # Tema Plymouth custom SOLEM: navy + gold sun orb
  # Render SVG → PNG via librsvg al build time. Plymouth richiede PNG raster.
  solemPlymouthTheme = pkgs.runCommand "solem-plymouth-theme" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    THEME_DIR="$out/share/plymouth/themes/solem"
    mkdir -p "$THEME_DIR"

    # Render logo + orb da SVG
    rsvg-convert -w 400 -h 100 ${../plymouth-theme/logo.svg} -o "$THEME_DIR/logo.png"
    rsvg-convert -w 120 -h 120 ${../plymouth-theme/orb.svg} -o "$THEME_DIR/orb.png"

    # Copia manifest + script
    cp ${../plymouth-theme/solem.plymouth} "$THEME_DIR/solem.plymouth"
    cp ${../plymouth-theme/solem.script} "$THEME_DIR/solem.script"
  '';
  cfg = config.solem.boot;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM BOOT — boot esperienza premium (no kernel logs scorrenti)
  # ──────────────────────────────────────────────────────────────────────
  options.solem.boot = {
    enable = lib.mkEnableOption "Plymouth splash + quiet boot SOLEM (navy+gold)";
  };

  config = lib.mkIf cfg.enable {

  boot.plymouth = {
    enable = true;
    # Tema CUSTOM SOLEM (navy + gold orb) — SVG renderizzato a PNG via librsvg
    theme = "solem";
    themePackages = [ solemPlymouthTheme ];
  };

  # Boot quieto: niente messaggi kernel scorrenti, solo splash
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
  ];

  # Consoleblank: schermo nero più rapido se idle
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # GRUB: timeout breve, menu disponibile per emergency rollback
  boot.loader.timeout = lib.mkDefault 3;

  # Bootloader theme — sfondo nero, niente distrazioni
  boot.loader.grub.splashImage = null;  # rimuove splash default GRUB

  };  # fin lib.mkIf cfg.enable
}
