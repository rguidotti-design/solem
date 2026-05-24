{ config, pkgs, lib, ... }:

# SOLEM VAULT — secret manager locale FOSS (no cloud, no account).
#
# Single responsibility: SOLO CLI `solem-vault` che gestisce secret
# (password, API keys, env vars) crittografati con age (FOSS, modern crypto).
#
# - Database: file singolo $HOME/.local/share/solem/vault.age (criptato)
# - Master key: file $HOME/.local/share/solem/vault-master.key (chmod 600)
# - Backup: copia chiave su USB con `vault export-key`
# - Sync: tramite Nextcloud/Syncthing del file .age cifrato (sicuro)
#
# Niente daemon, niente HTTP, niente network. Solo file locale + age.

let
  cfg = config.solem.vault;

  vaultCli = pkgs.writeShellApplication {
    name = "solem-vault";
    runtimeInputs = with pkgs; [ coreutils age wl-clipboard ];
    text = ''
      VAULT_DIR="$HOME/.local/share/solem"
      VAULT_FILE="$VAULT_DIR/vault.age"
      KEY_FILE="$VAULT_DIR/vault-master.key"
      mkdir -p "$VAULT_DIR"
      chmod 700 "$VAULT_DIR"

      ensure_key() {
        if [ ! -f "$KEY_FILE" ]; then
          echo "Genero master key in $KEY_FILE..."
          age-keygen -o "$KEY_FILE" 2>/dev/null
          chmod 600 "$KEY_FILE"
          echo "✓ Master key creata"
          echo "  Pubblica:  $(grep public "$KEY_FILE" || echo 'vedi file')"
          echo "  CRITICO:  salva backup chiave! USB / printout"
        fi
      }

      decrypt_vault() {
        if [ ! -f "$VAULT_FILE" ]; then
          echo "{}"  # vault vuoto JSON
        else
          age -d -i "$KEY_FILE" "$VAULT_FILE" 2>/dev/null || echo "{}"
        fi
      }

      encrypt_vault() {
        local DATA="$1"
        local PUBKEY
        PUBKEY=$(grep "public key:" "$KEY_FILE" | sed 's/.*: //')
        echo "$DATA" | age -e -r "$PUBKEY" -o "$VAULT_FILE"
        chmod 600 "$VAULT_FILE"
      }

      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in
        init)
          ensure_key
          if [ ! -f "$VAULT_FILE" ]; then
            encrypt_vault "{}"
            echo "✓ Vault inizializzato"
          fi
          ;;

        add|set)
          ensure_key
          KEY="''${1:?Usage: solem-vault add <key> [value]}"
          VAL="''${2:-}"
          if [ -z "$VAL" ]; then
            echo -n "Valore per '$KEY' (stdin, no echo): "
            stty -echo
            read -r VAL
            stty echo
            echo
          fi
          # Leggi vault corrente JSON
          CURRENT=$(decrypt_vault)
          # Aggiungi/aggiorna key (jq-less, simple sed/awk)
          # Per robustezza usa python via env
          NEW=$(python3 -c "
import json, sys
try: data = json.loads('''$CURRENT''')
except: data = {}
data['$KEY'] = '''$VAL'''
print(json.dumps(data, indent=2))
")
          encrypt_vault "$NEW"
          echo "✓ Salvato: $KEY"
          ;;

        get)
          KEY="''${1:?Usage: solem-vault get <key>}"
          DATA=$(decrypt_vault)
          VAL=$(python3 -c "
import json
try: data = json.loads('''$DATA''')
except: data = {}
print(data.get('$KEY', ''))
")
          if [ -z "$VAL" ]; then
            echo "(non trovato)" >&2
            exit 1
          fi
          echo "$VAL"
          ;;

        copy|cp)
          KEY="''${1:?Usage: solem-vault copy <key>}"
          VAL=$(solem-vault get "$KEY")
          if [ -n "$VAL" ]; then
            echo -n "$VAL" | wl-copy 2>/dev/null || echo "wl-copy non disponibile"
            echo "✓ Copiato in clipboard (10s)"
            ( sleep 10; echo -n "" | wl-copy 2>/dev/null ) &
          fi
          ;;

        list|ls)
          DATA=$(decrypt_vault)
          python3 -c "
import json
try: data = json.loads('''$DATA''')
except: data = {}
for k in sorted(data.keys()):
    print(f'  {k}')
"
          ;;

        rm|del)
          KEY="''${1:?Usage: solem-vault rm <key>}"
          DATA=$(decrypt_vault)
          NEW=$(python3 -c "
import json
try: data = json.loads('''$DATA''')
except: data = {}
data.pop('$KEY', None)
print(json.dumps(data, indent=2))
")
          encrypt_vault "$NEW"
          echo "✓ Rimosso: $KEY"
          ;;

        export-key)
          DEST="''${1:?Usage: solem-vault export-key <dest-file>}"
          cp "$KEY_FILE" "$DEST"
          chmod 600 "$DEST"
          echo "✓ Chiave esportata in: $DEST"
          echo "  ATTENZIONE: chiunque ha questo file può decifrare il vault."
          ;;

        import-key)
          SRC="''${1:?Usage: solem-vault import-key <src-file>}"
          cp "$SRC" "$KEY_FILE"
          chmod 600 "$KEY_FILE"
          echo "✓ Chiave importata"
          ;;

        export-vault)
          DEST="''${1:?Usage: solem-vault export-vault <dest>}"
          cp "$VAULT_FILE" "$DEST"
          echo "✓ Vault esportato (cifrato) in: $DEST"
          ;;

        status)
          echo "── SOLEM Vault ──"
          echo "Vault file: $VAULT_FILE"
          echo "Key file:   $KEY_FILE"
          if [ -f "$KEY_FILE" ]; then
            echo "Key:        sì (chmod $(stat -c %a "$KEY_FILE"))"
          else
            echo "Key:        no (esegui: solem-vault init)"
          fi
          if [ -f "$VAULT_FILE" ]; then
            COUNT=$(decrypt_vault | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))")
            echo "Vault:      $COUNT secret"
            echo "Size:       $(stat -c %s "$VAULT_FILE") bytes (cifrato)"
          else
            echo "Vault:      vuoto"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-vault — secret manager locale FOSS (age-encrypted)

  init                     genera master key + vault vuoto
  add <key> [value]        salva secret (se value omesso: prompt no-echo)
  get <key>                stampa secret
  copy <key>               copia in clipboard (auto-clear 10s)
  list                     elenca keys
  rm <key>                 rimuovi
  export-key <file>        backup chiave (es. su USB)
  import-key <file>        ripristina chiave da backup
  export-vault <file>      backup vault cifrato (per sync)
  status                   info vault

Use cases:
  solem-vault add github-pat
  export GITHUB_TOKEN=$(solem-vault get github-pat)
  solem-vault copy banking-password    # incolla nel browser

Storage:
  $HOME/.local/share/solem/vault.age          # database cifrato
  $HOME/.local/share/solem/vault-master.key   # chiave master (chmod 600)

Crypto: age (Adam Langley/Filippo Valsorda, FOSS, modern X25519).

Niente cloud, niente account, niente daemon. Tutto offline.
Sync sicuro: il file .age è già cifrato, puoi sincronizzarlo via
Nextcloud/Syncthing — anche se rubato, illeggibile senza chiave.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.vault = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-vault` secret manager age-encrypted locale";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vaultCli
      age           # crypto engine
      python3       # parsing JSON nei wrap
      wl-clipboard  # clipboard integration
    ];

    environment.etc."solem/vault.md".text = ''
      # SOLEM Vault

      Secret manager locale, cifrato con age (modern X25519).

      ## Setup primo uso

      ```
      solem-vault init        # genera master key
      solem-vault add github-pat
      solem-vault copy github-pat   # 10s in clipboard
      ```

      ## Backup chiave (CRITICO)

      Senza la master key, il vault è inaccessibile per sempre.

      ```
      solem-vault export-key /media/usb-backup/vault-master.key
      ```

      Salva su USB separato. Considera printout della chiave (è
      breve, 70 char circa) per backup paranoico.

      ## Sync multi-device

      Il file vault.age è già cifrato. Sicuro da sincronizzare:
        - Nextcloud sync $HOME/.local/share/solem/
        - Syncthing $HOME/.local/share/solem/
        - rsync su server self-host

      Anche se rubato il file, illeggibile senza master key.

      ## vs altri secret manager

      | Tool | FOSS | Cloud-free | Sync mio modo |
      |---|---|---|---|
      | 1Password | ❌ | ❌ | proprietario |
      | LastPass | ❌ | ❌ | proprietario |
      | Bitwarden self-host | ✅ | self-host | ✅ |
      | KeePassXC | ✅ | file locale | manuale |
      | pass (Unix) | ✅ | git | ✅ |
      | **solem-vault** | **✅** | **file age** | **qualsiasi sync** |
    '';
  };
}
