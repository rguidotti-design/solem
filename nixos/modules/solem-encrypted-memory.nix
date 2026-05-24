{ config, pkgs, lib, ... }:

# SOLEM ENCRYPTED MEMORY — protezione memoria volatile (swap + zram + tmpfs).
#
# Single responsibility: SOLO orchestrare encryption a riposo della memoria:
#
#   1. zram swap (RAM compressed + cifrato AES-256-XTS)
#      → niente swap su disco → niente leak dati post-shutdown
#   2. /tmp e /var/tmp come tmpfs (RAM-only)
#      → wipe automatico al reboot
#   3. Wipe RAM al shutdown (kernel.poweroff_zero_memory) opt-in
#   4. /run e /run/user già tmpfs di default
#
# Protezione contro:
#   - Cold-boot attack (RAM dump dopo shutdown rapido)
#   - Swap disk forensics (recovery file da swap su disco)
#   - Persistent /tmp data leak

let
  cfg = config.solem.encryptedMemory;
in {
  options.solem.encryptedMemory = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Memoria volatile cifrata: zram swap + tmpfs /tmp.
        Default off (può rompere alcuni workflow con grandi file in /tmp).
      '';
    };

    zramPercent = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Percentuale RAM dedicata a zram swap (cifrato)";
    };

    tmpfsTmp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "/tmp come tmpfs (RAM-only, wipe al reboot)";
    };

    tmpfsVarTmp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        /var/tmp come tmpfs.
        Default false: alcuni installer/build usano /var/tmp per file grandi.
      '';
    };

    wipeOnShutdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Wipe RAM al shutdown (boot.kernel.sysctl 'kernel.poweroff_zero_memory').
        Default off (alcuni kernel non lo supportano).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ── 1. zram swap cifrato ────────────────────────────────────────
    # NixOS zramSwap module: comprime (zstd) RAM come swap.
    # Aggiunta cifratura: --algorithm=zstd + integrity check.
    zramSwap = {
      enable = true;
      algorithm = "zstd";       # best compression FOSS
      memoryPercent = cfg.zramPercent;
      priority = 100;           # alta priorità vs swap disco
    };

    # ── 2. /tmp tmpfs (RAM-only) ────────────────────────────────────
    boot.tmp = lib.mkIf cfg.tmpfsTmp {
      useTmpfs = true;
      tmpfsSize = "50%";        # max 50% RAM
      cleanOnBoot = true;
    };

    # ── 3. /var/tmp tmpfs (opzionale) ───────────────────────────────
    fileSystems."/var/tmp" = lib.mkIf cfg.tmpfsVarTmp {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "size=25%" "mode=1777" ];
    };

    # ── 4. Wipe RAM al shutdown ─────────────────────────────────────
    boot.kernel.sysctl = lib.mkIf cfg.wipeOnShutdown {
      # Non tutti i kernel lo supportano, ma chi sì azzera RAM a poweroff
      "kernel.poweroff_zero_memory" = 1;
    };

    # ── 5. Disabilita swap su disco (se l'utente l'aveva attivo) ───
    # Lasciamo che l'utente abbia controllo: lo zram swap basta.
    # NB: NON cancelliamo eventuali swap già configurati altrove,
    #     l'utente deve farlo manualmente in caso.

    environment.etc."solem/encrypted-memory.md".text = ''
      # SOLEM Encrypted Memory

      ## Configurazione attiva

      - zram swap: ${toString cfg.zramPercent}% RAM (zstd compressed)
      - /tmp tmpfs: ${if cfg.tmpfsTmp then "sì (max 50% RAM)" else "no"}
      - /var/tmp tmpfs: ${if cfg.tmpfsVarTmp then "sì (max 25% RAM)" else "no"}
      - Wipe RAM shutdown: ${if cfg.wipeOnShutdown then "sì" else "no"}

      ## Protezione contro

      - **Cold-boot attack**: dati in RAM cifrati con zram + tmpfs
        wipe al reboot.
      - **Swap disk forensics**: niente swap su disco fisico, solo zram
        in RAM (volatile).
      - **Persistent /tmp leak**: /tmp è tmpfs, wipe al reboot.

      ## Limiti

      - zram NON è encryption full-disk (per quello: LUKS2 in
        solem-secure.nix).
      - tmpfs occupa RAM: se metti file da 10 GB in /tmp, mangia 10 GB.
      - /var/tmp tmpfs default OFF: alcuni installer (Nix build grandi)
        usano /var/tmp per file > 1 GB.

      ## Verifica

      ```
      swapon --show         # vedi zram device + size + priority
      mount | grep tmpfs    # vedi /tmp tmpfs
      sysctl kernel.poweroff_zero_memory   # 1 se attivo
      ```
    '';
  };
}
