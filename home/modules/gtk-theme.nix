{ config, lib, pkgs, ... }:

# SOLEM GTK theme — navy + gold + Cormorant + Inter.
{
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";    # base FOSS GNOME
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Inter";
      size = 11;
    };
    gtk3.extraCss = ''
      window decoration {
        border: 1px solid #D4A24A33;
      }
      headerbar {
        background: #0B1426;
        color: #F5F5F5;
      }
      headerbar:focus button.suggested-action {
        background: #D4A24A;
        color: #0B1426;
      }
    '';
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";    # uniforma Qt al tema GTK
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.gnome-themes-extra;
    size = 24;
    gtk.enable = true;
  };

  # Variabili ambiente coerenti
  home.sessionVariables = {
    GTK_THEME = "Adwaita-dark";
    QT_QPA_PLATFORMTHEME = "gtk2";
  };
}
