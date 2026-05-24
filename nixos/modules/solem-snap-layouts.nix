{ config, pkgs, lib, ... }:

# SOLEM SNAP LAYOUTS — Snap Layouts Windows 11 style su Hyprland.
#
# Single responsibility: SOLO config Hyprland keybinds per:
# - Super + Arrow → snap finestra a metà schermo
# - Super + Shift + Arrow → snap a quarto
# - Super + numpad: 1-9 → snap a posizione griglia 3x3
#
# Bind file separato che l'utente sourcing in ~/.config/hypr/hyprland.conf:
#   source = /etc/xdg/solem/hypr-snap-layouts.conf

let
  cfg = config.solem.snapLayouts;

  hyprBinds = pkgs.writeText "solem-snap-layouts.conf" ''
    # ── SOLEM Snap Layouts — Windows 11 style su Hyprland ──────────

    # Snap a metà schermo
    bind = SUPER, Left,  exec, hyprctl dispatch resizeactive exact 50% 100% ; hyprctl dispatch moveactive exact 0 0
    bind = SUPER, Right, exec, hyprctl dispatch resizeactive exact 50% 100% ; hyprctl dispatch moveactive exact 50% 0
    bind = SUPER, Up,    exec, hyprctl dispatch resizeactive exact 100% 50% ; hyprctl dispatch moveactive exact 0 0
    bind = SUPER, Down,  exec, hyprctl dispatch resizeactive exact 100% 50% ; hyprctl dispatch moveactive exact 0 50%

    # Snap a quarto (Super + Shift + freccia diagonale)
    bind = SUPER SHIFT, Left,  exec, hyprctl dispatch resizeactive exact 50% 50%  ; hyprctl dispatch moveactive exact 0 0
    bind = SUPER SHIFT, Right, exec, hyprctl dispatch resizeactive exact 50% 50%  ; hyprctl dispatch moveactive exact 50% 0
    bind = SUPER SHIFT, Up,    exec, hyprctl dispatch resizeactive exact 50% 50%  ; hyprctl dispatch moveactive exact 0 50%
    bind = SUPER SHIFT, Down,  exec, hyprctl dispatch resizeactive exact 50% 50%  ; hyprctl dispatch moveactive exact 50% 50%

    # Snap a tre colonne (Super + Alt + 1/2/3)
    bind = SUPER ALT, 1, exec, hyprctl dispatch resizeactive exact 33% 100% ; hyprctl dispatch moveactive exact 0 0
    bind = SUPER ALT, 2, exec, hyprctl dispatch resizeactive exact 33% 100% ; hyprctl dispatch moveactive exact 33% 0
    bind = SUPER ALT, 3, exec, hyprctl dispatch resizeactive exact 33% 100% ; hyprctl dispatch moveactive exact 67% 0

    # Maximize / Restore (Super + M)
    bind = SUPER, M, fullscreen, 1

    # Center floating (Super + C)
    bind = SUPER, C, centerwindow

    # Floating toggle (Super + V)
    bind = SUPER, V, togglefloating

    # ── Workspaces 1-9 (Windows-style) ──────────────────────────────
    bind = SUPER, 1, workspace, 1
    bind = SUPER, 2, workspace, 2
    bind = SUPER, 3, workspace, 3
    bind = SUPER, 4, workspace, 4
    bind = SUPER, 5, workspace, 5
    bind = SUPER, 6, workspace, 6
    bind = SUPER, 7, workspace, 7
    bind = SUPER, 8, workspace, 8
    bind = SUPER, 9, workspace, 9
  '';
in {
  options.solem.snapLayouts = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bind Hyprland Snap Layouts Windows-style in /etc/xdg/solem/";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."xdg/solem/hypr-snap-layouts.conf".source = hyprBinds;

    # Helper README
    environment.etc."xdg/solem/hypr-snap-layouts.README" = {
      text = ''
        SOLEM Snap Layouts — bind Windows-style per Hyprland

        Per attivare, aggiungi in ~/.config/hypr/hyprland.conf:

            source = /etc/xdg/solem/hypr-snap-layouts.conf

        Bind:
          Super + ← →    snap a metà sinistra/destra
          Super + ↑ ↓    snap a metà superiore/inferiore
          Super + Shift + freccia  → snap a quarto
          Super + Alt + 1/2/3      → snap a 3 colonne
          Super + M                 → maximize
          Super + C                 → center floating
          Super + V                 → toggle floating
          Super + 1-9               → workspace
      '';
    };
  };
}
