{ config, pkgs, lib, ... }:

let
  cfg = config.solem.secrets;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM SECRETS — sops-nix scaffold dichiarativo
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO gestione segreti via sops-nix.
  # Allineamento Prompt Master v4.0 sez. 2.2.
  #
  # NB: il flake deve aggiungere input "sops-nix" prima di attivare questo
  # modulo. Per ora scaffold + check assertions.
  #
  # Flow tipico:
  #   1. Utente genera chiave age (age-keygen) e la salva in /var/lib/sops-nix/key.txt
  #   2. Cripta secret.yaml con sops + chiave age corrispondente
  #   3. Committa secret.yaml cifrato nel repo
  #   4. Al boot sops-nix decripta in /run/secrets/<nome>
  #   5. Servizi referenziano /run/secrets/<nome> tramite EnvironmentFile

  options.solem.secrets = {
    enable = lib.mkEnableOption "sops-nix per gestione segreti dichiarativa";

    defaultSopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/default.yaml;
      description = "File sops cifrato di default (committabile in git).";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = "Path chiave age per decifrare (NON in git).";
    };

    secretsDeclaration = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Mappa di segreti da decifrare. Esempio:
          {
            "gavio-groq-api-key" = {
              owner = "gavio";
              group = "users";
              mode = "0600";
            };
          }
        Il file cifrato deve contenere le chiavi corrispondenti.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Assertion: sops-nix deve essere disponibile (richiede flake input)
    assertions = [{
      assertion = builtins.hasAttr "sops" config;
      message = ''
        solem.secrets.enable = true richiede l'input "sops-nix" nel flake.nix.
        Aggiungi:
          inputs.sops-nix.url = "github:Mic92/sops-nix";
        E in nixosConfigurations:
          modules = [ inputs.sops-nix.nixosModules.sops ... ];
      '';
    }];

    # NB: la config reale `sops.*` verrà attivata solo dopo l'aggiunta input.
    # Qui solo manifest per documentare cosa si abilita.

    environment.etc."solem/secrets-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      sops_default_file = toString cfg.defaultSopsFile;
      age_key_file = cfg.ageKeyFile;
      secrets_declared = builtins.attrNames cfg.secretsDeclaration;
      generate_age_key = "age-keygen -o ${cfg.ageKeyFile}";
      encrypt_example = "sops --encrypt --age $(cat ${cfg.ageKeyFile}.pub) secrets/raw.yaml > secrets/default.yaml";
    };
  };
}
