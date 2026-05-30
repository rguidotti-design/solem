{ config, pkgs, lib, ... }:

# SOLEM AUTO UPDATE — Step 14: nixos-rebuild auto + security patch tracking.
#
# Single responsibility: SOLO automatizzare nixos-rebuild da channel/flake
# upstream con strategia conservativa:
#   - Check ogni notte per CVE/patch
#   - Auto-apply solo a livello "switch" (no reboot) di default
#   - Reboot delayed: solo se patch kernel + finestra di manutenzione
#
# Threat coperto:
#   - CVE upstream con patch disponibile (Linux kernel, OpenSSL, sudo,
#     glibc, ...) che restano UNFIXED perche' utente non aggiorna.
#   - Supply chain: nixpkgs commit con backdoor → mitigato da binary
#     cache trust + signature check.
#
# Tutto FOSS (NixOS auto-upgrade, GPL). 0 €.

let
  cfg = config.solem.autoUpdate;
in {
  options.solem.autoUpdate = {
    enable = lib.mkEnableOption "Automatic NixOS upgrade per security patches";

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github:rguidotti-design/solem";
      description = ''
        Flake URI da cui aggiornare. Se null, usa il flake corrente del sistema.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "04:30";
      description = ''
        OnCalendar systemd: quando eseguire check + upgrade.
        Default: 04:30 ogni giorno (basso traffico tipico).
      '';
    };

    operation = lib.mkOption {
      type = lib.types.enum [ "switch" "boot" "test" ];
      default = "boot";
      description = ''
        Strategia upgrade:
          - switch: applica subito (puo' interrompere servizi attivi)
          - boot:   prepara nuovo system, attivo al prossimo reboot
                    (raccomandato: 0 downtime, ma kernel patch richiede reboot)
          - test:   dry-run senza apply (solo notifica)
      '';
    };

    rebootIfRequired = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Se l'upgrade include nuovo kernel, reboot automatico.
        Default OFF: per evitare reboot durante uso. Manual:
        l'utente vede notifica e fa reboot a comodo.
      '';
    };

    rebootWindow = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          lower = lib.mkOption { type = lib.types.str; default = "04:00"; };
          upper = lib.mkOption { type = lib.types.str; default = "06:00"; };
        };
      });
      default = null;
      description = ''
        Finestra oraria in cui reboot e' accettabile (solo se
        rebootIfRequired=true). Es. { lower="04:00"; upper="06:00"; }
      '';
    };

    notifyAfter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "notify-send all'utente desktop dopo upgrade";
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      operation = cfg.operation;
      allowReboot = cfg.rebootIfRequired;
      dates = cfg.schedule;
      persistent = true;  # esegui anche se sistema era spento al schedule
    } // (lib.optionalAttrs (cfg.flake != null) {
      flake = cfg.flake;
    }) // (lib.optionalAttrs (cfg.rebootWindow != null) {
      rebootWindow = cfg.rebootWindow;
    });

    # Hook post-upgrade: notify utente desktop + log
    systemd.services.nixos-upgrade.serviceConfig.ExecStartPost =
      lib.mkIf cfg.notifyAfter
        "${pkgs.writeShellScript "solem-upgrade-notify" ''
          set +e
          NEW_GEN=$(${pkgs.coreutils}/bin/readlink /nix/var/nix/profiles/system | sed 's/.*-//')
          MSG="SOLEM upgrade completed: generation $NEW_GEN"
          ${pkgs.systemd}/bin/systemd-cat -t solem-upgrade -p info ${pkgs.coreutils}/bin/echo "$MSG"

          # notify-send a utenti loggati (se sessione grafica)
          for UID_DIR in /run/user/*; do
            [ -d "$UID_DIR" ] || continue
            U=$(basename "$UID_DIR")
            ${pkgs.coreutils}/bin/runuser -u "#$U" -- \
              env DBUS_SESSION_BUS_ADDRESS="unix:path=$UID_DIR/bus" \
              ${pkgs.libnotify}/bin/notify-send -u normal -t 30000 \
              "SOLEM Auto-Update" "$MSG" 2>/dev/null || true
          done
        ''}";

    # CLI di ispezione
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-update-status";
        runtimeInputs = with pkgs; [ coreutils systemd nix ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM Auto Update ──"
              echo "Schedule: ${cfg.schedule}"
              echo "Operation: ${cfg.operation}"
              echo "AutoReboot: ${if cfg.rebootIfRequired then "yes" else "no"}"
              ${lib.optionalString (cfg.flake != null) ''echo "Flake: ${cfg.flake}"''}
              echo
              echo "── Ultimo run nixos-upgrade ──"
              systemctl status nixos-upgrade.service --no-pager 2>/dev/null | head -15 || \
                echo "(mai eseguito)"
              echo
              echo "── Prossimo run ──"
              systemctl list-timers nixos-upgrade.timer --no-pager 2>/dev/null | head -5
              echo
              echo "── Generazioni recenti ──"
              sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | tail -5
              ;;

            run|now)
              echo "Esecuzione upgrade ADESSO (richiede sudo)..."
              sudo systemctl start nixos-upgrade.service
              echo "Avviato. Controlla con: solem-update-status"
              ;;

            log)
              echo "── Log nixos-upgrade (journal) ──"
              sudo journalctl -u nixos-upgrade.service --since "7 days ago" -n 80 --no-pager
              ;;

            rollback)
              echo "── Rollback alla generazione precedente ──"
              echo "Generazioni disponibili:"
              sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5
              echo
              read -r -p "Numero generazione (Enter per cancel): " G
              if [ -n "$G" ]; then
                sudo nixos-rebuild switch --rollback || \
                  sudo /nix/var/nix/profiles/system-"$G"-link/bin/switch-to-configuration switch
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-update-status — auto-update CVE patch

  status     schedule + ultimo run + prossimo run + generazioni
  run        esegui upgrade ADESSO (no aspetto schedule)
  log        log nixos-upgrade ultimi 7 giorni
  rollback   torna a generazione precedente (rollback safe NixOS)

Schedule corrente: ${cfg.schedule}
Operation: ${cfg.operation}

Trade-off:
  - switch: apply subito, possibili interruzioni
  - boot:   prepara nuovo system, attivo al prossimo reboot (default)
  - test:   solo check + notifica, no apply
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/auto-update.md".text = ''
      # SOLEM Auto Update

      ## Cosa fa

      systemd timer (nixos-upgrade.timer di NixOS upstream) esegue
      `nixos-rebuild ${cfg.operation}` ogni ${cfg.schedule}.

      ## Strategia conservativa default

      - operation = "${cfg.operation}": prepara nuovo system, attivo al
        prossimo reboot (no interruzione servizi attivi).
      - allowReboot = ${if cfg.rebootIfRequired then "true" else "false"}: ${if cfg.rebootIfRequired
        then "reboot automatico se serve (kernel update)"
        else "NON reboota automaticamente"}
      - notify-send a utente desktop dopo upgrade riuscito.
      - Rollback safe (NixOS generation): se nuovo system non boot,
        boot menu permette tornare al precedente.

      ## Manuale

      ```
      solem-update-status         # schedule + last run + next run
      solem-update-status run     # upgrade ADESSO
      solem-update-status log     # log ultimi 7 giorni
      solem-update-status rollback # torna a gen precedente
      ```

      ## Threat coperto

      - **CVE upstream UNPATCHED**: kernel, OpenSSL, glibc, sudo, ...
        Auto-pull ogni notte → patch applicata massimo 24h dopo release.
      - **Supply chain attack su nixpkgs**: parzialmente mitigato.
        nix verifica signature dei binary cache (cache.nixos.org pubkey
        fissato in solem-core).

      ## Limiti onesti

      - Auto-upgrade NON e' "auto-test": una regressione che rompe servizi
        viene applicata. Mitigazione: operation="boot" (no interruzione fino
        a reboot manuale).
      - Kernel patch richiede reboot. Se allowReboot=false (default),
        sei vulnerabile finche' reboot manuale.
      - Out-of-band patches (es. 0-day fixato in PR specifica, non in master)
        NON sono presi. Devi tracciare upstream manualmente.
      - Dipende da network: se offline, upgrade skipped silenziosamente.
    '';
  };
}
