{ config, pkgs, lib, ... }:

# SOLEM DEMO — mostra capability del sistema in 30 secondi.
#
# Single responsibility: SOLO CLI `solem-demo` che esegue diagnostica
# rapida e mostra cosa funziona. Niente config sistema modificato.

let
  cfg = config.solem.demo;

  demoCli = pkgs.writeShellApplication {
    name = "solem-demo";
    runtimeInputs = with pkgs; [ coreutils systemd curl gum jq ];
    text = ''
      # Header
      gum style \
        --foreground 220 --border-foreground 220 --border double \
        --align center --width 60 --padding "1 2" \
        'SOLEM Demo' \
        '' \
        'AI-native OS · 30 secondi · 0 €'

      # ── 1. Sistema ──────────────────────────────────────────────
      gum style --bold "1/6 — Sistema"
      echo "  Hostname:  $(hostname)"
      echo "  Kernel:    $(uname -r)"
      echo "  Uptime:    $(uptime -p)"
      echo "  Memoria:   $(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
      sleep 1

      # ── 2. SOLEM CLI ─────────────────────────────────────────────
      gum style --bold "2/6 — SOLEM CLI"
      if command -v solem >/dev/null 2>&1; then
        solem status 2>/dev/null | head -10 || echo "  solem CLI ok"
      else
        echo "  ⚠ solem CLI non installato"
      fi
      sleep 1

      # ── 3. GAVIO API ─────────────────────────────────────────────
      gum style --bold "3/6 — GAVIO API (:8000)"
      if curl -s -m 2 http://127.0.0.1:8000/health 2>/dev/null | jq -r '.status' 2>/dev/null; then
        echo "  GAVIO OK"
      else
        echo "  ⚠ GAVIO non risponde (avvialo con: gavio-server &)"
      fi
      sleep 1

      # ── 4. SOLEM API ─────────────────────────────────────────────
      gum style --bold "4/6 — SOLEM API (:8001)"
      if curl -s -m 2 http://127.0.0.1:8001/solem/health 2>/dev/null | head -c 80; then
        echo "  SOLEM API OK"
      else
        echo "  ⚠ SOLEM API non attivo (solem.api.enable = true)"
      fi
      echo
      sleep 1

      # ── 5. Network ───────────────────────────────────────────────
      gum style --bold "5/6 — Network"
      echo "  Interfacce: $(ip -o link show | wc -l) interfacce"
      echo "  Default route: $(ip route show default | awk 'NR==1 {print $5}')"
      sleep 1

      # ── 6. Servizi SOLEM attivi ─────────────────────────────────
      gum style --bold "6/6 — Servizi SOLEM attivi"
      for svc in gavio solem-api solem-keep solem-update solem-backup; do
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        if [ "$STATUS" = "active" ]; then
          gum style --foreground 46 "  ● $svc"
        else
          gum style --foreground 244 "  ○ $svc ($STATUS)"
        fi
      done

      echo
      gum style \
        --foreground 46 --border-foreground 46 --border rounded \
        --align center --width 60 --padding "1 2" \
        'Demo completato.' \
        '' \
        'Prossimo: solem-doctor per diagnosi completa'
    '';
  };
in {
  options.solem.demo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa il comando `solem-demo` (tour capability sistema)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ demoCli ];
  };
}
