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
        gaps_in = 8
        gaps_out = 16
        border_size = 2
        col.active_border = rgba(c9a961ee) rgba(2c5f9dee) rgba(0a1628ee) 45deg
        col.inactive_border = rgba(1a284088)
        layout = dwindle
        allow_tearing = false
        resize_on_border = true
        extend_border_grab_area = 12
        hover_icon_on_border = true
    }

    decoration {
        rounding = 10
        active_opacity = 1.0
        inactive_opacity = 0.96
        fullscreen_opacity = 1.0
        blur {
            enabled = true
            size = 8
            passes = 3
            new_optimizations = true
            xray = true
            ignore_opacity = true
            noise = 0.012
            contrast = 1.08
            brightness = 0.94
            vibrancy = 0.18
            vibrancy_darkness = 0.5
        }
        drop_shadow = yes
        shadow_range = 18
        shadow_render_power = 4
        shadow_ignore_window = true
        col.shadow = rgba(00000080)
        col.shadow_inactive = rgba(00000040)
        dim_inactive = true
        dim_strength = 0.08
        dim_special = 0.3
        dim_around = 0.4
    }

    animations {
        enabled = yes
        # Bezier "navy" — easing premium tipo macOS Sequoia
        bezier = navy,        0.16, 1.00, 0.30, 1.00
        bezier = navyOut,     0.55, 0.00, 0.45, 1.00
        bezier = navyBounce,  0.34, 1.56, 0.64, 1.00
        bezier = navyFast,    0.05, 0.90, 0.10, 1.00

        # Window: pop-in con scale + fade
        animation = windows,         1, 6,  navy,       popin 92%
        animation = windowsIn,       1, 7,  navyBounce, popin 88%
        animation = windowsOut,      1, 5,  navyOut,    popin 92%
        animation = windowsMove,     1, 5,  navy
        animation = border,          1, 12, navy
        animation = borderangle,     1, 80, navy,       loop
        animation = fade,            1, 6,  navy
        animation = fadeIn,          1, 5,  navyFast
        animation = fadeOut,         1, 7,  navyOut

        # Workspaces: slide orizzontale fluido (3D-ish)
        animation = workspaces,      1, 7,  navy,       slidefadevert 25%
        animation = specialWorkspace,1, 8,  navyBounce, slidevert
    }

    dwindle {
        pseudotile = yes
        preserve_split = yes
        smart_split = yes
        smart_resizing = true
        force_split = 0
    }

    master {
        new_status = master
        mfact = 0.55
    }

    misc {
        force_default_wallpaper = 0
        disable_hyprland_logo = true
        disable_splash_rendering = true
        background_color = 0x0a1628
        animate_manual_resizes = true
        animate_mouse_windowdragging = true
        focus_on_activate = true
        new_window_takes_over_fullscreen = 2
    }

    # ─── Window rules: Stage Manager-like behaviour ───────────────────
    # Floating per app dialog/utility, tile per produttività
    windowrulev2 = float, class:^(org.kde.dolphin)$
    windowrulev2 = float, class:^(pavucontrol)$
    windowrulev2 = float, class:^(blueman-manager)$
    windowrulev2 = float, title:^(Picture-in-Picture)$
    windowrulev2 = pin,   title:^(Picture-in-Picture)$
    windowrulev2 = float, class:^(.*Authenticator.*)$
    windowrulev2 = size 80% 80%, class:^(firefox|chromium|librewolf)$,floating:1
    # GAVIO overlay always-on-top + sticky
    windowrulev2 = float,   title:^(SOLEM Overlay)$
    windowrulev2 = pin,     title:^(SOLEM Overlay)$
    windowrulev2 = size 720 520, title:^(SOLEM Overlay)$
    windowrulev2 = center,  title:^(SOLEM Overlay)$
    windowrulev2 = noborder, title:^(SOLEM Overlay)$

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

    # ─── Scratchpad / Stage Manager-like ───
    # Special workspace "gavio" → slide-up dal basso, sticky
    bind = $mainMod, grave, togglespecialworkspace, gavio
    bind = $mainMod SHIFT, grave, movetoworkspace, special:gavio

    # ─── Touchpad gesture: 3-finger swipe workspace (3D-ish) ───
    gestures {
        workspace_swipe = true
        workspace_swipe_fingers = 3
        workspace_swipe_distance = 320
        workspace_swipe_invert = true
        workspace_swipe_min_speed_to_force = 30
        workspace_swipe_cancel_ratio = 0.5
        workspace_swipe_create_new = true
        workspace_swipe_forever = true
    }

    # ─── Hot corner: top-left → universal search Cmd+K-like ───
    # (Hyprland non ha hot corners native, ma simuliamo con bind)
    bind = $mainMod CTRL, K, exec, fuzzel
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
