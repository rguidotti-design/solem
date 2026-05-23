{ pkgs }:

pkgs.nixosTest {
  name = "solem-quick-settings";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-quick-settings.nix ];
    solem.quickSettings.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Tutti i toggle CLI presenti
    for tool in ["solem-toggle-wifi", "solem-toggle-bt", "solem-toggle-vpn",
                 "solem-toggle-focus", "solem-toggle-airplane"]:
        machine.succeed(f"which {tool}")

    # eww + brightnessctl + pamixer + wireplumber installati
    for pkg in ["eww", "brightnessctl", "pamixer", "wpctl"]:
        machine.succeed(f"which {pkg}")

    # Config eww scritto
    machine.succeed("test -e /etc/xdg/solem/eww/eww.yuck")
  '';
}
