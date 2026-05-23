{ pkgs }:

pkgs.nixosTest {
  name = "solem-italian-locale";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../modules/solem-italian-locale.nix ];
    solem.italianLocale.enable = true;
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Locale generato
    out = machine.succeed("locale -a")
    assert "it_IT.utf8" in out or "it_IT.UTF-8" in out, f"locale missing: {out}"

    # Timezone Italia
    out = machine.succeed("cat /etc/timezone || readlink -f /etc/localtime")
    assert "Rome" in out, f"timezone wrong: {out}"

    # Hunspell italiano
    machine.succeed("which hunspell")
    machine.succeed("test -e $(dirname $(readlink -f $(which hunspell)))/../share/hunspell/it_IT.aff || find /nix/store -name 'it_IT.aff' | head -1")
  '';
}
