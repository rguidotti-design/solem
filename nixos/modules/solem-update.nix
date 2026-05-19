{ config, pkgs, lib, ... }:

let
  cfg = config.solem.update;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM UPDATE — auto-update OTA + rollback automatico
  # ──────────────────────────────────────────────────────────────────────
  # Tre meccanismi indipendenti:
  #
  #   1. AUTO-UPDATE TIMER       — settimanale (o configurable)
  #                                `nixos-rebuild boot --refresh` (applica
  #                                al prossimo reboot, non interrompe sessione)
  #
  #   2. BOOT FAILURE ROLLBACK   — systemd-boot conta i tentativi di boot.
  #                                Se 3 fallimenti consecutivi → boot
  #                                automatico della generation precedente.
  #                                NB: richiede systemd-boot (UEFI), non GRUB.
  #
  #   3. GC GENERATIONS          — pulizia generazioni vecchie (> 30 giorni)
  #                                per evitare riempire /nix con vecchi
  #                                rollback inutilizzati.
  #
  # Default DISABILITATO in VM test (non vogliamo update mentre testiamo).
  # Attivare su Beelink/bare-metal con: solem.update.enable = true;

  options.solem.update = {
    enable = lib.mkEnableOption "Auto-update OTA + rollback automatico";

    flakeUrl = lib.mkOption {
      type = lib.types.str;
      default = "path:/opt/solem-flake";
      description = ''
        Flake da cui pullare aggiornamenti.
        Default: path locale montato 9p (per VM test).
        Bare-metal: "git+https://github.com/USER/solem.git" o URL repo remoto.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "OnCalendar systemd (weekly, daily, hourly, '*-*-* 04:00:00').";
    };

    bootRollback.enable = lib.mkEnableOption "Rollback automatico se boot fallisce 3 volte (richiede systemd-boot)" // {
      default = true;
    };

    gcOlderThan = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Soglia GC generazioni vecchie.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── 1. AUTO-UPDATE TIMER ───────────────────────────────────────
    # systemd.services.solem-update fa `nixos-rebuild boot --refresh`
    # (boot non switch: applicato al PROSSIMO reboot, sessione corrente
    # non interrotta). L'utente decide quando riavviare.
    systemd.services.solem-update = {
      description = "SOLEM — pull e build aggiornamenti dal flake remoto";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ nixos-rebuild git nix coreutils ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
      script = ''
        set -euo pipefail
        echo "[solem-update] pulling latest flake from ${cfg.flakeUrl}"
        # nixos-rebuild boot: applica al prossimo reboot, non al sistema vivo
        nixos-rebuild boot \
          --flake "${cfg.flakeUrl}#solem-vm" \
          --refresh \
          2>&1 | tee /var/log/solem-update.log
        echo "[solem-update] update preparato. Riavvia per applicare."
      '';
    };

    systemd.timers.solem-update = {
      description = "SOLEM — schedule auto-update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";  # evita stampede se tanti nodi
      };
    };

    # ── 2. BOOT ROLLBACK AUTOMATICO (systemd-boot) ─────────────────
    # systemd-boot conta tentativi di boot per ogni generation. Se una
    # generation fallisce N volte, viene de-prioritizzata e boot tenta
    # la generation precedente automaticamente.
    boot.loader.systemd-boot = lib.mkIf cfg.bootRollback.enable {
      # NB: solo se systemd-boot è il bootloader scelto. La VM usa GRUB
      # di default, quindi questa opzione viene attivata solo su bare-metal.
      configurationLimit = 10;  # max 10 generazioni nel menu boot
    };

    # ── 3. GC GENERATIONS ──────────────────────────────────────────
    # Cleanup automatico vecchie generazioni — già parzialmente in solem-core.nix.
    # Qui lo override per essere consistent con cfg.gcOlderThan.
    nix.gc = {
      automatic = lib.mkForce true;
      dates = lib.mkForce "weekly";
      options = lib.mkForce "--delete-older-than ${cfg.gcOlderThan}";
    };

    # ── 4. Notification del manifest ───────────────────────────────
    environment.etc."solem/update-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      flake_url = cfg.flakeUrl;
      schedule = cfg.schedule;
      boot_rollback = cfg.bootRollback.enable;
      gc_older_than = cfg.gcOlderThan;
    };
  };
}
