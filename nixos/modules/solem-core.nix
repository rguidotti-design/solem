{ config, pkgs, lib, ... }:

{
  # Layer base SOLEM: utente operatore, Nix tuning, journald, GC.

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
    # Mirror italiano per velocità (opzionale, fallback automatico)
    substituters = [ "https://cache.nixos.org/" ];
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
