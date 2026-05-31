{ config, pkgs, lib, ... }:

# SOLEM MULTI TENANT — Step 45: family accounts + guest session.
#
# Single responsibility: SOLO creazione utenti family + guest ephemeral.
# Single-tenant "gavio" rimane, ma ora utenti aggiuntivi opzionali.

let
  cfg = config.solem.multiTenant;
in {
  options.solem.multiTenant = {
    enable = lib.mkEnableOption "Family accounts + guest session";

    familyUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          uid = lib.mkOption { type = lib.types.int; };
          name = lib.mkOption { type = lib.types.str; example = "Alice"; };
          hashedPassword = lib.mkOption {
            type = lib.types.str;
            description = "openssl passwd -6 <password>";
          };
          isAdmin = lib.mkOption { type = lib.types.bool; default = false; };
          parentalControls = lib.mkOption { type = lib.types.bool; default = false; };
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          alice = { uid = 1001; name = "Alice"; hashedPassword = "$6$..."; };
          bob   = { uid = 1002; name = "Bob"; hashedPassword = "$6$..."; isAdmin = true; };
          kid   = { uid = 1003; name = "Kid"; hashedPassword = "$6$..."; parentalControls = true; };
        }
      '';
    };

    enableGuest = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Guest session ephemeral (home /tmp, no persist)";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = (lib.mapAttrs (uname: u: {
      isNormalUser = true;
      uid = u.uid;
      description = u.name;
      hashedPassword = u.hashedPassword;
      shell = pkgs.bash;
      extraGroups = (lib.optional u.isAdmin "wheel")
        ++ [ "users" "video" "audio" "input" "networkmanager" ];
    }) cfg.familyUsers) // (lib.optionalAttrs cfg.enableGuest {
      guest = {
        isNormalUser = true;
        uid = 9999;
        description = "Guest (sessione ephemeral)";
        hashedPassword = "";  # no password
        home = "/tmp/guest-home";
        createHome = false;
      };
    });

    systemd.tmpfiles.rules = lib.mkIf cfg.enableGuest [
      "d /tmp/guest-home 0700 guest users -"
    ];

    # Parental controls: configurable per-user
    # NOTA: parental controls completo richiede moduli aggiuntivi (es. dans-guardian)
    # Qui solo flag, applicato manualmente
    environment.etc."solem/multi-tenant.md".text = ''
      # SOLEM Multi-Tenant Family (Step 45)

      Utenti aggiuntivi family + guest opt-in.

      ## Setup family user
      ```nix
      solem.multiTenant = {
        enable = true;
        familyUsers = {
          alice = {
            uid = 1001;
            name = "Alice";
            hashedPassword = "$6$..."; # openssl passwd -6 mypass
            isAdmin = false;
          };
          bob = {
            uid = 1002;
            name = "Bob";
            hashedPassword = "$6$...";
            isAdmin = true;  # wheel/sudo
          };
        };
        enableGuest = true;
      };
      ```

      Poi: nixos-rebuild switch → utenti creati.

      ## Switch user
      Da GDM/greetd: logout → login screen → seleziona altro user.
      Da CLI: `loginctl list-sessions`, `loginctl activate <session>`.

      ## Guest session
      Home in /tmp/guest-home (no persist tra reboot).
      Default no password (anyone can use).
      Per restrict: aggiungi hashedPassword.

      ## Parental controls (TODO)
      Flag `parentalControls = true` riservato. Implementazione
      completa richiede futuro Step 45b con:
      - DNS filter (squid/dnsmasq blocklist)
      - App whitelist (AppArmor profili per-user)
      - Time limits (systemd loginctl quota)
      - Screen time reporting

      ## Limiti onesti
      - Hashed password in flake.nix = committable to git (rischio).
        SOLUZIONE: usa sops-nix / agenix per secret encryption.
      - Switch user UX dipende dal greetd/GDM configurato.
      - GAVIO single-tenant: ogni user che vuole GAVIO deve avere il
        suo gavio-ai-<user> (TODO Step 45c per-user AI sandbox).
    '';
  };
}
