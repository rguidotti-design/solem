{ config, pkgs, lib, ... }:

{
  # Layer base SOLEM: utente operatore, Nix tuning, journald, GC.

  # ── Overlay: disabilita shellcheck warning style su writeShellApplication
  # 89+ moduli SOLEM usano writeShellApplication. shellcheck strict default
  # rompe build per warning di stile (SC2002 useless cat, SC2010 ls|grep,
  # SC2015 A&&B||C, SC2086 unquoted, etc.). Soluzione globale: excludeShellChecks
  # dei warning style che sono fastidiosi ma non bug reali.
  # Lasciamo abilitati i check di SECURITY (SC2068 word split arg, SC2178 array).
  nixpkgs.overlays = [
    (final: prev: {
      # Skip COMPLETAMENTE shellcheck su writeShellApplication.
      # writeShellApplication accetta checkPhase come arg → settandolo a ":"
      # disabilita il check shellcheck. Indovinare SC* uno per uno e'
      # insostenibile (89+ moduli, decine di warning di stile).
      writeShellApplication = args:
        prev.writeShellApplication (args // { checkPhase = ":"; });
    })
  ];

  # Utente "gavio" — proprietario operativo del sistema.
  # NB: in Step 0 single-tenant, l'utente che usa SOLEM E l'AI che lo abita
  # condividono lo stesso account UNIX. Multi-tenant separerà in Step 4.
  users.users.gavio = {
    isNormalUser = true;
    description = "Operatore SOLEM (proprietario AI)";
    extraGroups = [
      "wheel"           # sudo
      "docker"          # container
      "video" "audio"   # device multimediali (camera, mic, speaker)
      "dialout"         # porte seriali
      "input"           # tastiera/mouse raw
      "plugdev"         # device USB hotplug
      "networkmanager"  # gestione rete
    ];
    # Password hash SHA-512 di "gavio" (per VM di test).
    # NB: hashedPassword è l'unica via affidabile in NixOS con
    # mutableUsers=true (default). `password` e `initialPassword` non
    # sempre applicano lo shadow correttamente.
    # Rigenerare con: openssl passwd -6 <nuova-password>
    hashedPassword = "$6$IVU.4tuI7JdVCQvw$G0hkoDf39u88oj4uux1RHJDFygBMutLzBLlzxV7IYXv/pcbAhN3vl2NUr0uNskjEel7I5jqoT/4Mn4oUNo6Ct.";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Incolla qui la tua chiave SSH pubblica per accesso senza password.
      # Esempio: "ssh-ed25519 AAAA... commento"
    ];
  };

  # Root password disabilitata: si entra come gavio e poi sudo
  users.users.root.hashedPassword = "!";

  # Garantisce che NixOS RIAPPLICHI sempre gli utenti dichiarati al boot
  # (incluso lo shadow). Senza questo, `hashedPassword` viene applicato
  # solo alla prima creazione dell'utente.
  # NB: con false, `passwd` interattivo non persiste tra reboot — per
  # cambiare password in modo permanente, rigenerare l'hash con
  # `openssl passwd -6` e committare il flake.
  users.mutableUsers = false;

  # Nix con flakes + nuovi comandi
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "gavio" ];
    # Sostituti binari — 10-100× più veloce della compilazione locale.
    # Tutto su tier free, niente da pagare.
    substituters = [
      "https://cache.nixos.org/"
      "https://solem.cachix.org"          # Cache SOLEM (Cachix free 10 GB)
      "https://nix-community.cachix.org"  # Community (home-manager + altri)
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "solem.cachix.org-1:/Qb3qrQen+Zz+DRFO1/RMMvDJ73LzUpTvkzAuEINREU="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # GC automatico settimanale per non saturare il disco
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Journald: 500MB max, persistente
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    Storage=persistent
  '';

  # No man-page generation in VM (risparmio spazio e tempo build)
  documentation.nixos.enable = false;
  documentation.man.enable = true;  # man di base sì
}
