{ config, lib, pkgs, ... }:

# SOLEM mako (notification daemon) user-side config — auto in ~/.config/mako/config.
# Tema navy + gold + Inter (uguale a /etc/xdg/solem/mako/config).
{
  xdg.configFile."mako/config".text = ''
    font=Inter 11
    width=400
    height=140
    padding=12,18
    border-size=2
    border-radius=10
    background-color=#0B1426E6
    border-color=#D4A24A
    text-color=#F5F5F5
    progress-color=over #D4A24A33
    layer=overlay
    anchor=top-right
    margin=12
    default-timeout=5000
    sort=-time
    max-visible=5
    max-history=200
    group-by=app-name

    [urgency=low]
    border-color=#D4A24A77
    default-timeout=3000

    [urgency=critical]
    border-color=#FF5555
    default-timeout=0
    background-color=#1A0B0BE6

    [app-name=GAVIO]
    border-color=#7B9EFF
  '';
}
