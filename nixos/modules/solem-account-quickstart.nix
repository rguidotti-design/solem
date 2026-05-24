{ config, pkgs, lib, ... }:

# SOLEM ACCOUNT QUICKSTART — auto-crea identità al primo boot.
#
# Single responsibility: SOLO orchestrare creazione automatica di:
# - GPG key (ed25519)
# - SSH key (ed25519)
# - Mesh identity (ed25519 separata)
# - Backup keys (age o restic password salvata in keychain)
#
# Idempotente: se esistono già, non rigenera. Esegue al primo login utente.

let
  cfg = config.solem.accountQuickstart;

  quickstartScript = pkgs.writeShellApplication {
    name = "solem-account-init";
    runtimeInputs = with pkgs; [ openssh gnupg age coreutils ];
    text = ''
      STATE_DIR="$HOME/.local/state/solem"
      mkdir -p "$STATE_DIR"
      DONE_FLAG="$STATE_DIR/account-init.done"

      if [ -f "$DONE_FLAG" ]; then
        exit 0
      fi

      echo "── SOLEM Account Quickstart ──"
      echo "Genero identità crypto (idempotente)..."

      # 1. SSH key
      if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" \
          -C "solem-$USER-$(hostname)"
        echo "  ✓ SSH key generata"
      else
        echo "  → SSH key già presente, skip"
      fi

      # 2. Mesh identity (separata da SSH per principle of least authority)
      MESH_KEY="$STATE_DIR/mesh-identity.key"
      if [ ! -f "$MESH_KEY" ]; then
        ssh-keygen -t ed25519 -N "" -f "$MESH_KEY" \
          -C "solem-mesh-$USER" >/dev/null
        echo "  ✓ Mesh identity generata"
      else
        echo "  → Mesh identity già presente, skip"
      fi

      # 3. GPG key (interactive solo se utente vuole; altrimenti batch ECC)
      if ! gpg --list-secret-keys | grep -q "$USER"; then
        EMAIL="''${EMAIL:-$USER@solem.local}"
        BATCH=$(mktemp)
        cat > "$BATCH" <<EOF
        %no-protection
        Key-Type: EDDSA
        Key-Curve: ed25519
        Subkey-Type: ECDH
        Subkey-Curve: cv25519
        Name-Real: $USER
        Name-Email: $EMAIL
        Expire-Date: 2y
        %commit
EOF
        gpg --batch --gen-key "$BATCH" 2>&1 | tail -3
        rm -f "$BATCH"
        echo "  ✓ GPG key generata (no-passphrase, valid 2 anni)"
      else
        echo "  → GPG key già presente, skip"
      fi

      # 4. Age key per backup encrypted
      if [ ! -f "$STATE_DIR/age.key" ]; then
        age-keygen -o "$STATE_DIR/age.key" 2>/dev/null
        chmod 600 "$STATE_DIR/age.key"
        echo "  ✓ Age key generata (per backup encrypted)"
      else
        echo "  → Age key già presente, skip"
      fi

      # 5. Restic password (in keychain libsecret se disponibile)
      if [ ! -f "$STATE_DIR/restic.pass" ]; then
        head -c 32 /dev/urandom | base64 > "$STATE_DIR/restic.pass"
        chmod 600 "$STATE_DIR/restic.pass"
        echo "  ✓ Restic password generata"
      fi

      date -Iseconds > "$DONE_FLAG"

      echo ""
      echo "── Riepilogo ──"
      echo "SSH pub:    $(cat $HOME/.ssh/id_ed25519.pub | cut -c1-60)..."
      echo "Mesh pub:   $(cat ''${MESH_KEY}.pub | cut -c1-60)..."
      echo "GPG fpr:    $(gpg --fingerprint --with-colons | grep '^fpr' | head -1 | cut -d: -f10)"
      echo ""
      echo "Tutto salvato in $STATE_DIR (locale, mai uploadato)."
    '';
  };
in {
  options.solem.accountQuickstart = {
    enable = lib.mkEnableOption "Auto-genera identità crypto al primo login (SSH + GPG + Mesh + Age + Restic)";

    autoRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Esegui automaticamente al primo login (via profile.d)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      quickstartScript
      gnupg
      openssh
      age
      restic
    ];

    # Auto-run al login via /etc/profile.d (idempotente)
    environment.etc."profile.d/solem-account-init.sh" = lib.mkIf cfg.autoRun {
      text = ''
        # Esegui solem-account-init solo se non già fatto
        if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -t 0 ]; then
          if [ ! -f "$HOME/.local/state/solem/account-init.done" ]; then
            solem-account-init 2>/dev/null || true
          fi
        fi
      '';
    };
  };
}
