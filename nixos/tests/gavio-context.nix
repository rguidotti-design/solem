{ pkgs }:

pkgs.nixosTest {
  name = "solem-gavio-context";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-gavio-context.nix ];
    solem.gavioContext.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # CLI principale presente
    machine.succeed("which solem-gavio-ctx")

    # Tutti i tool richiesti installati
    for tool in ["wl-copy", "wl-paste", "grim", "slurp", "tesseract",
                 "notify-send", "jq", "curl"]:
        machine.succeed(f"which {tool}")

    # Hyprland binds file scritto
    machine.succeed("test -e /etc/xdg/solem/hypr-gavio-binds.conf")

    # `solem-gavio-ctx help` non crasha
    machine.succeed("solem-gavio-ctx help 2>&1 | head -3")
  '';
}
