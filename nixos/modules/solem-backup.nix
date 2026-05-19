{ config, pkgs, lib, ... }:

let
  backupScript = pkgs.writeShellScript "solem-backup" ''
    set -euo pipefail

    BACKUP_DIR=/var/backups/solem
    mkdir -p "$BACKUP_DIR"

    TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
    OUT="$BACKUP_DIR/solem-snap-$TIMESTAMP.tar.zst"

    # Cosa salvare: tutto lo stato persistente che NON è ricreabile da Nix
    SOURCES=(
      /var/lib/gavio
      /var/lib/solem
      /etc/gavio
    )

    # Salta sorgenti vuote/inesistenti
    EXISTING=()
    for s in "''${SOURCES[@]}"; do
      [ -e "$s" ] && EXISTING+=("$s")
    done

    if [ ''${#EXISTING[@]} -eq 0 ]; then
      echo "[solem-backup] niente da salvare"
      exit 0
    fi

    echo "[solem-backup] snapshot → $OUT"
    ${pkgs.gnutar}/bin/tar \
      --use-compress-program='${pkgs.zstd}/bin/zstd -3' \
      -cf "$OUT" \
      --warning=no-file-changed \
      "''${EXISTING[@]}" || true

    # Retention: tieni ultimi 14 snapshot (≈ 2 settimane se giornaliero)
    ls -1t "$BACKUP_DIR"/solem-snap-*.tar.zst 2>/dev/null \
      | tail -n +15 \
      | xargs -r rm -v

    echo "[solem-backup] done. Snapshot esistenti:"
    ls -lh "$BACKUP_DIR"/solem-snap-*.tar.zst 2>/dev/null | tail -5
  '';
in {
  # SOLEM BACKUP — snapshot quotidiano dello stato persistente.
  # Cattura: dati GAVIO (venv state, dataset, conversazioni), stato SOLEM
  # (identity, context, memory), env file (/etc/gavio).
  # NON cattura: /nix/store (ricostruibile dal flake), log volatili.

  systemd.services.solem-backup = {
    description = "SOLEM — snapshot stato persistente";
    serviceConfig = {
      Type = "oneshot";
      User = "root";  # serve leggere /etc/gavio/env (chmod 600)
      ExecStart = backupScript;
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.solem-backup = {
    description = "SOLEM backup — quotidiano alle 04:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;  # se la VM era spenta, esegue alla riaccensione
      RandomizedDelaySec = "10m";
    };
  };

  # Directory backup con ownership corretto
  systemd.tmpfiles.rules = [
    "d /var/backups/solem 0750 root root -"
  ];

  # Aggiungi zstd ai system packages per ispezione manuale degli archivi
  environment.systemPackages = with pkgs; [ zstd ];
}
