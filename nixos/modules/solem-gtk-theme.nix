{ config, pkgs, lib, ... }:

# SOLEM GTK THEME — custom navy/gold theme per GNOME/GTK apps.
# Genera gtk.css override + icon scheme color accent gold.

let
  cfg = config.solem.gtkTheme;

  solemThemeDir = pkgs.runCommand "solem-gtk-theme" { } ''
    THEME_DIR=$out/share/themes/SOLEM-Navy
    mkdir -p $THEME_DIR/gtk-3.0 $THEME_DIR/gtk-4.0

    # GTK 3 + 4 override (estende Adwaita-dark con accent #D4A24A)
    cat > $THEME_DIR/gtk-3.0/gtk.css <<'EOF'
/* SOLEM Navy/Gold theme — extends Adwaita-dark */
@define-color theme_selected_bg_color #D4A24A;
@define-color theme_selected_fg_color #0B1426;
@define-color accent_color #D4A24A;
@define-color accent_bg_color #D4A24A;
@define-color accent_fg_color #0B1426;
@define-color theme_bg_color #0B1426;
@define-color theme_base_color #1A2540;
@define-color window_bg_color #0B1426;
@define-color window_fg_color #F5F5F5;
@define-color view_bg_color #1A2540;
@define-color view_fg_color #F5F5F5;
@define-color headerbar_bg_color #1A2540;
@define-color headerbar_fg_color #F5F5F5;
@define-color headerbar_border_color #D4A24A;
@define-color sidebar_bg_color #0B1426;
@define-color sidebar_fg_color #F5F5F5;

window, .background {
  background-color: #0B1426;
  color: #F5F5F5;
}

headerbar, .titlebar {
  background: linear-gradient(to bottom, #1A2540, #0B1426);
  color: #F5F5F5;
  border-bottom: 1px solid rgba(212, 162, 74, 0.3);
}

button.suggested-action {
  background: #D4A24A;
  color: #0B1426;
  font-weight: 600;
}
button.suggested-action:hover {
  background: #E0B864;
}

scrollbar slider {
  background-color: #D4A24A;
  min-width: 6px;
}

entry, textview text {
  background-color: rgba(212, 162, 74, 0.08);
  color: #F5F5F5;
  border: 1px solid rgba(212, 162, 74, 0.2);
}

entry:focus {
  border-color: #D4A24A;
  box-shadow: 0 0 0 2px rgba(212, 162, 74, 0.3);
}

row:selected, .view:selected {
  background-color: rgba(212, 162, 74, 0.2);
  color: #F5F5F5;
}

.activatable:hover {
  background-color: rgba(212, 162, 74, 0.1);
}

switch:checked {
  background: #D4A24A;
}

progressbar progress, levelbar block.filled {
  background: #D4A24A;
}

tooltip {
  background-color: #1A2540;
  color: #F5F5F5;
  border: 1px solid #D4A24A;
}
EOF

    cp $THEME_DIR/gtk-3.0/gtk.css $THEME_DIR/gtk-4.0/gtk.css

    # Index theme
    cat > $THEME_DIR/index.theme <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=SOLEM-Navy
Comment=SOLEM navy/gold theme (extends Adwaita-dark)

[X-GNOME-Metatheme]
GtkTheme=SOLEM-Navy
IconTheme=Adwaita
CursorTheme=Adwaita
EOF
  '';
in {
  options.solem.gtkTheme = {
    enable = lib.mkEnableOption "Custom GTK theme navy/gold SOLEM";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ solemThemeDir ];

    # Override gtk-theme a SOLEM-Navy via programs.dconf (NixOS-native).
    programs.dconf = {
      enable = true;
      profiles.user.databases = [{
        settings."org/gnome/desktop/interface" = {
          gtk-theme = "SOLEM-Navy";
          color-scheme = "prefer-dark";
        };
      }];
    };
  };
}
