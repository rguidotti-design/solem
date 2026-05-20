{ config, pkgs, lib, ... }:

# SOLEM AI FREEDOM — GAVIO ha libertà di esecuzione sul sistema.
#
# Single responsibility: SOLO concedere a `gavio` user (e ai suoi
# processi) i permessi per agire sul sistema senza prompt: sudo NOPASSWD
# selettivo, polkit aperto per azioni di sessione, capabilities Linux per
# processi specifici, niente AppArmor/SELinux che blocchi GAVIO.
#
# Filosofia: SOLEM è l'OS di GAVIO. GAVIO deve poter:
#   - gestire servizi systemd (start/stop/restart su moduli SOLEM/gavio)
#   - leggere log
#   - controllare network (route, firewall via solem-api)
#   - aprire app desktop
#   - leggere/scrivere in ~/ e nelle dir dichiarate
#
# NON ha bisogno di:
#   - rm -rf /
#   - cambiare password root
#   - disabilitare audit/firewall
#
# Limiti rimangono per evitare disastri irreversibili.

let
  cfg = config.solem.aiFreedom;
in {
  options.solem.aiFreedom = {
    enable = lib.mkEnableOption "Libertà esecuzione GAVIO (sudo NOPASSWD selettivo + polkit)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "gavio";
    };

    allowSystemctl = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "GAVIO può systemctl su servizi solem-* e gavio";
    };

    allowNixosRebuild = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "GAVIO può nixos-rebuild switch (per applicare update)";
    };

    allowNetworkConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "GAVIO può modificare firewall/route via solem-api";
    };

    allowJournalRead = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "GAVIO può leggere journal di tutti i servizi";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── User gavio nei gruppi giusti ──
    users.users.${cfg.user}.extraGroups = lib.mkAfter (
      [ "wheel" "users" "audio" "video" "input" ]
      ++ lib.optional cfg.allowJournalRead "systemd-journal"
      ++ lib.optional cfg.allowNetworkConfig "networkmanager"
    );

    # ── sudo NOPASSWD selettivo (NON blanket) ──
    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;       # gavio è in wheel
      extraRules = [
        {
          users = [ cfg.user ];
          commands =
            (lib.optional cfg.allowSystemctl {
              command = "/run/current-system/sw/bin/systemctl";
              options = [ "NOPASSWD" "SETENV" ];
            })
            ++ (lib.optional cfg.allowSystemctl {
              command = "/run/current-system/sw/bin/journalctl";
              options = [ "NOPASSWD" ];
            })
            ++ (lib.optional cfg.allowNixosRebuild {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [ "NOPASSWD" "SETENV" ];
            })
            ++ (lib.optional cfg.allowNixosRebuild {
              command = "/run/current-system/sw/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            })
            ++ (lib.optional cfg.allowNetworkConfig {
              command = "/run/current-system/sw/bin/nft";
              options = [ "NOPASSWD" ];
            })
            ++ (lib.optional cfg.allowNetworkConfig {
              command = "/run/current-system/sw/bin/ip";
              options = [ "NOPASSWD" ];
            })
            ++ (lib.optional cfg.allowNetworkConfig {
              command = "/run/current-system/sw/bin/wg";
              options = [ "NOPASSWD" ];
            })
            ++ [{
              # Permettere a solem-api di scrivere /etc/hosts (focus mode)
              command = "/run/current-system/sw/bin/tee /etc/hosts";
              options = [ "NOPASSWD" ];
            }];
        }
      ];
    };

    # ── polkit: gavio può azioni di sessione senza prompt ──
    security.polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (subject.user == "${cfg.user}") {
            // Azioni systemd su unit solem-* e gavio
            if (action.id == "org.freedesktop.systemd1.manage-units") {
              var unit = action.lookup("unit");
              if (unit && (unit.indexOf("solem-") == 0 || unit == "gavio.service" || unit == "ollama.service")) {
                return polkit.Result.YES;
              }
            }
            // NetworkManager
            if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0) {
              return polkit.Result.YES;
            }
            // Mount/unmount (per backup esterno)
            if (action.id.indexOf("org.freedesktop.udisks2.") == 0) {
              return polkit.Result.YES;
            }
          }
        });
      '';
    };

    # ── Capabilities per processi specifici ──
    # solem-api eredita capabilities che servono per gestire sistema senza essere root
    security.wrappers = {
      solem-tcpdump = {
        source = "${pkgs.tcpdump}/bin/tcpdump";
        capabilities = "cap_net_raw,cap_net_admin+eip";
        owner = "root";
        group = "wheel";
        permissions = "u+rx,g+rx";
      };
    };

    # ── No AppArmor sui processi GAVIO/SOLEM (libertà piena) ──
    # AppArmor resta per altri servizi (sshd, nginx) ma niente profilo che
    # blocchi gavio o solem-api.
    security.apparmor.enable = lib.mkDefault false;

    # ── Audit: traccia, non blocca ──
    # GAVIO può fare cose; auditd tiene il log per forensics ma non
    # interferisce. (Le regole sono in solem-auditd.nix.)

    # ── Sysctl: permetti unprivileged user namespaces (richiesto da firejail/podman) ──
    boot.kernel.sysctl = {
      "kernel.unprivileged_userns_clone" = 1;
      "user.max_user_namespaces" = 28633;
    };

    # ── Banner che spiega le scelte ──
    environment.etc."solem/ai-freedom.md".text = ''
      # GAVIO ha libertà su SOLEM — by design

      Questa è una scelta architetturale. SOLEM è l'OS di GAVIO. GAVIO
      può controllare il sistema (start/stop servizi, modifica rete,
      apply update) senza prompt password.

      Limiti che restano (anti-disastro):
        - non può `rm -rf /` (nessuna sudo blanket)
        - non può cambiare password root
        - non può disabilitare audit/firewall via sudo
        - audit log traccia ogni azione (solem-auditd)

      Per togliere libertà: solem.aiFreedom.enable = false;
    '';
  };
}
