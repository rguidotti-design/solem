{ config, pkgs, lib, ... }:

# Auto-config Hyprland user-side: sourcing dei binds SOLEM
# (gavio-context, spotlight, quick-settings) automaticamente.

{
  xdg.configFile."hypr/hyprland.conf".text = ''
    # SOLEM Hyprland — config user generato da home-manager
    # Override personali in ~/.config/hypr/hyprland-user.conf

    # ── Monitor (auto-detect via kanshi) ──────────────────────────────
    monitor = , preferred, auto, 1

    # ── Programmi default ─────────────────────────────────────────────
    $terminal = alacritty
    $browser = librewolf
    $launcher = anyrun

    # ── Bind SOLEM (sourced da /etc/xdg/solem/) ───────────────────────
    source = /etc/xdg/solem/hypr-gavio-binds.conf

    # ── Keybind essenziali ────────────────────────────────────────────
    bind = SUPER, Return,   exec, $terminal
    bind = SUPER, B,        exec, $browser
    bind = SUPER, Space,    exec, $launcher              # Spotlight-style
    bind = SUPER, Q,        killactive
    bind = SUPER SHIFT, Q,  exit
    bind = SUPER, F,        fullscreen
    bind = SUPER, L,        exec, hyprlock                # Lock screen
    bind = SUPER, V,        togglefloating
    bind = SUPER, J,        togglesplit

    # Screenshot
    bind = , Print,         exec, grim -g "$(slurp)" - | wl-copy
    bind = SHIFT, Print,    exec, grim ~/Pictures/solem/$(date +%Y%m%d-%H%M%S).png

    # Volume & brightness
    bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
    bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindel = , XF86AudioMute,        exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bindel = , XF86MonBrightnessUp,  exec, brightnessctl set +5%
    bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

    # Workspace switch
    bind = SUPER, 1, workspace, 1
    bind = SUPER, 2, workspace, 2
    bind = SUPER, 3, workspace, 3
    bind = SUPER, 4, workspace, 4
    bind = SUPER, 5, workspace, 5

    # Move window to workspace
    bind = SUPER SHIFT, 1, movetoworkspace, 1
    bind = SUPER SHIFT, 2, movetoworkspace, 2
    bind = SUPER SHIFT, 3, movetoworkspace, 3
    bind = SUPER SHIFT, 4, movetoworkspace, 4
    bind = SUPER SHIFT, 5, movetoworkspace, 5

    # ── Autostart ─────────────────────────────────────────────────────
    exec-once = mako --config /etc/xdg/solem/mako/config
    exec-once = waybar
    exec-once = kanshi -c /etc/xdg/solem/kanshi/config
    exec-once = fusuma -c /etc/xdg/solem/fusuma/config.yml
    exec-once = wl-paste --type text --watch cliphist store
    exec-once = wl-paste --type image --watch cliphist store

    # Override personale (se presente)
    source = ~/.config/hypr/hyprland-user.conf
  '';

  # Crea il file di override vuoto se non esiste (per `source = ...` sopra)
  home.file.".config/hypr/hyprland-user.conf" = {
    text = "# Personalizzazioni Hyprland (modifica liberamente)\n";
    force = false;   # non sovrascrivere se l'utente ha già modificato
  };
}
