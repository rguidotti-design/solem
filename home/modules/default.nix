# SOLEM Home Manager modules — auto-symlink config user-side.
#
# Single responsibility: SOLO collegare i config sparsi in /etc/xdg/solem/*
# ai path canonici ~/.config/* dove le app li cercano.
#
# Risolve il problema "ho installato il modulo ma il config non parte".
{
  hyprland     = ./hyprland.nix;
  mako         = ./mako.nix;
  eww          = ./eww.nix;
  fusuma       = ./fusuma.nix;
  kanshi       = ./kanshi.nix;
  waybar       = ./waybar.nix;
  shell        = ./shell.nix;
  gtk-theme    = ./gtk-theme.nix;
}
