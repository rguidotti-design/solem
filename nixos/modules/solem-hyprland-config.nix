{ config, pkgs, lib, ... }:

# SOLEM HYPRLAND CONFIG — config Hyprland branded navy + Waybar.
#
# Single responsibility: SOLO scrivere config Hyprland + Waybar in
# /etc/xdg/. Niente install del compositor (è in solem-desktop.nix).
#
# Branding: navy palette, gradient bordi gold, Cormorant font, animazioni
# smooth ma sobrie (no compiz-cubo).

let
  cfg = config.solem.hyprlandConfig;

  hyprlandConf = pkgs.writeText "hyprland.conf" ''
    # SOLEM Hyprland config — navy palette + Cormorant
    # Wayland-only compositor moderno.

    monitor=,preferred,auto,1

    exec-once = waybar
    exec-once = mako
    exec-once = wl-paste --watch cliphist store
    exec-once = swayidle -w \
      timeout 600 'swaylock' \
      timeout 900 'wlr-randr --output "*" --off' resume 'wlr-randr --output "*" --on'

    env = XCURSOR_SIZE,24
    env = QT_QPA_PLATFORMTHEME,qt6ct
    env = MOZ_ENABLE_WAYLAND,1

    input {
        kb_layout = it
        kb_options = caps:escape
        follow_mouse = 1
        touchpad {
            natural_scroll = yes
            tap-to-click = yes
            disable_while_typing = yes
        }
        sensitivity = 0
    }

    general {
        gaps_in = 6
        gaps_out = 12
        border_size = 2
        col.active_border = rgba(c9a961ee) rgba(0a1628ee) 45deg
        col.inactive_border = rgba(1a284088)
        layout = dwindle
        allow_tearing = false
    }

    decoration {
        rounding = 8
        blur {
            enabled = true
            size = 6
            passes = 2
            new_optimizations = true
            xray = false
        }
        drop_shadow = yes
        shadow_range = 8
        shadow_render_power = 3
        col.shadow = rgba(0a1628aa)
    }

    animations {
        enabled = yes
        bezier = navy, 0.16, 1, 0.3, 1
        animation = windows, 1, 5, navy
        animation = windowsOut, 1, 5, navy, popin 80%
        animation = border, 1, 8, default
        animation = fade, 1, 4, default
        animation = workspaces, 1, 4, navy
    }

    dwindle {
        pseudotile = yes
        preserve_split = yes
        smart_split = yes
    }

    misc {
        force_default_wallpaper = 0
        disable_hyprland_logo = true
        background_color = 0x0a1628
    }

    # ─── Keybinds ─────────────────────────────────────────────────────
    $mainMod = SUPER

    bind = $mainMod, RETURN, exec, foot
    bind = $mainMod, Q, killactive,
    bind = $mainMod, M, exit,
    bind = $mainMod, E, exec, nautilus
    bind = $mainMod, V, togglefloating,
    bind = $mainMod, SPACE, exec, fuzzel
    bind = $mainMod, P, pseudo,
    bind = $mainMod, J, togglesplit,
    bind = $mainMod, F, fullscreen,
    bind = $mainMod, L, exec, swaylock
    bind = $mainMod SHIFT, S, exec, solem-shot region
    bind = ,Print, exec, solem-shot full
    bind = $mainMod SHIFT, C, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy

    # Move focus
    bind = $mainMod, left,  movefocus, l
    bind = $mainMod, right, movefocus, r
    bind = $mainMod, up,    movefocus, u
    bind = $mainMod, down,  movefocus, d

    # Workspaces 1-10
    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod, 0, workspace, 10

    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5

    # Volume / brightness (laptop)
    bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
    bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindel = ,XF86AudioMute,        exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bindel = ,XF86MonBrightnessUp,   exec, brightnessctl set 5%+
    bindel = ,XF86MonBrightnessDown, exec, brightnessctl set 5%-

    # Mouse drag/resize floating
    bindm = $mainMod, mouse:272, movewindow
    bindm = $mainMod, mouse:273, resizewindow
  '';
in {
  options.solem.hyprlandConfig = {
    enable = lib.mkEnableOption "Config Hyprland branded SOLEM (navy + Cormorant)";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."xdg/hypr/hyprland.conf".source = hyprlandConf;

    # Pacchetti correlati (compositor stesso è in solem-desktop)
    environment.systemPackages = with pkgs; [
      foot          # terminale Wayland-native
      fuzzel        # launcher
      brightnessctl
      wpctl
      wl-clipboard
    ];
  };
}
