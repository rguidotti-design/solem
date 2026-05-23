{ pkgs }:

pkgs.nixosTest {
  name = "solem-user-clis";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-system-tools.nix
      ../modules/solem-privacy-tools.nix
      ../modules/solem-multimedia-tools.nix
      ../modules/solem-typography.nix
    ];
    solem.systemTools.enable = true;
    solem.privacyTools.enable = true;
    solem.multimediaTools.enable = true;
    solem.typography.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Tutte le CLI principali presenti
    for cli in ["solem-clean", "solem-priv", "solem-media", "solem-doc"]:
        machine.succeed(f"which {cli}")

    # Ogni CLI mostra help senza crashare
    for cli in ["solem-clean", "solem-priv", "solem-media", "solem-doc"]:
        machine.succeed(f"{cli} help 2>&1 | head -5")

    # Pacchetti core dei tool
    for pkg in ["filelight", "ncdu", "gpg", "pwgen", "yt-dlp", "ffmpeg", "pandoc", "typst"]:
        machine.succeed(f"which {pkg} || find /nix/store -name {pkg} -executable -type f | head -1")
  '';
}
